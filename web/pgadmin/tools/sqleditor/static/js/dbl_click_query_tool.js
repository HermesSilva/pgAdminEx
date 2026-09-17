/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

/* Double-clicking an object in the Object Explorer opens the Query Tool, in
 * the manner of DBeaver: a table or view gets a SELECT limited to a
 * configurable number of rows, run straight away; anything else gets its
 * CREATE script, loaded but not run. Governed by the
 * 'dbl_click_opens_query_tool' browser preference.
 */

import _ from 'lodash';
import url_for from 'sources/url_for';
import pgAdmin from 'sources/pgadmin';
import { getRandomInt } from 'sources/utils';
import getApiInstance from '../../../../static/js/api_instance';
import { BROWSER_PANELS } from '../../../../browser/static/js/constants';
import usePreferences from '../../../../preferences/static/js/store';
import { QUERY_TOOL_EVENTS } from './components/QueryToolConstants';

/* Nodes a SELECT can be run against. Kept in step with the View/Edit Data
 * menus in SQLEditorModule, which support the same set. */
export const SELECTABLE_NODES = [
  'table', 'view', 'mview', 'foreign_table', 'catalog_object', 'partition',
];

/* Event carrying a fresh query into an already-open Query Tool panel. The
 * per-panel event bus is not reachable from the tree, so this goes through
 * the global browser bus and each panel picks out its own id. */
export const DBL_CLICK_RUN_QUERY = 'pgadmin:query_tool:dbl_click_run_query';

/* Panels opened by double-click, keyed by the object they were opened for,
 * so double-clicking the same table returns to its tab while a different
 * table gets one of its own - in the manner of DBeaver. Panels the user
 * opened themselves are never recorded here and so never reused. */
const reusablePanels = new Map();

export function panelKeyFor(parentData, nodeData) {
  /* Server and database identify the session; the object's own type and id
   * make the key unique within it. Ids repeat across servers and across
   * databases, so all four parts are needed. */
  if(!parentData?.server?._id || !parentData?.database?._id ||
      !nodeData?._type || nodeData?._id === undefined) {
    return null;
  }
  return `${parentData.server._id}/${parentData.database._id}` +
    `/${nodeData._type}/${nodeData._id}`;
}

export function quoteIdent(name) {
  /* Quote an identifier for inclusion in generated SQL. Unlike the usual
   * pgAdmin path, this SQL is built in the client, so the object's own name
   * - which a user with CREATE rights chooses freely, and which may contain
   * a quote character - must not be able to break out of the statement and
   * append SQL of its own. Doubling embedded quotes is what PostgreSQL's
   * quote_ident() does. */
  return `"${String(name).replace(/"/g, '""')}"`;
}

export function buildSelectSql(schemaName, objectName, limit) {
  const qualified = schemaName
    ? `${quoteIdent(schemaName)}.${quoteIdent(objectName)}`
    : quoteIdent(objectName);
  return `SELECT * FROM ${qualified}\n\tLIMIT ${parseInt(limit, 10)};`;
}

export function getSchemaName(parentData) {
  /* Mirrors retrieveNameSpaceName() in show_view_data.js: an object hangs
   * off a schema, a catalog, or a view (for a partition). */
  return parentData?.schema?._label ?? parentData?.catalog?._label
    ?? parentData?.view?._label ?? null;
}

/* Whether double-click should act on this node at all. Collection nodes
 * ('coll-table' and friends) and the containers above them keep their
 * expand/collapse behaviour, which is how the tree is navigated. */
export function shouldHandleNode(nodeData, node) {
  if(!nodeData?._type || nodeData._type.includes('coll-')) {
    return false;
  }
  if(SELECTABLE_NODES.includes(nodeData._type)) {
    return true;
  }
  /* Everything else needs a CREATE script to show. A node advertises that
   * through hasScriptTypes; without it there is nothing to open, so leave
   * the double-click to the tree. */
  return Boolean(node?.hasScriptTypes?.includes?.('create'));
}

export function isEnabled() {
  const prefs = usePreferences.getState().getPreferencesForModule('browser');
  return Boolean(prefs?.dbl_click_opens_query_tool);
}

export function getRowLimit() {
  const prefs = usePreferences.getState().getPreferencesForModule('browser');
  const limit = parseInt(prefs?.dbl_click_row_limit, 10);
  /* Guard the generated SQL against a missing or nonsensical preference
   * rather than emitting 'LIMIT NaN'. */
  return (Number.isFinite(limit) && limit > 0) ? limit : 1000;
}

function panelIdFor(transId) {
  return `${BROWSER_PANELS.QUERY_TOOL}_${transId}`;
}

export function opensInNewBrowserTab() {
  const prefs = usePreferences.getState().getPreferencesForModule('browser');
  return Boolean(prefs?.new_browser_tab_open?.includes?.('qt'));
}

/* Hand the query to a panel this same feature opened earlier for the given
 * database, if it is still around. Returns true when one took it. */
function reuseExistingPanel(dbKey, sql, autoRun) {
  const transId = reusablePanels.get(dbKey);
  if(!transId) {
    return false;
  }

  const panelId = panelIdFor(transId);
  const docker = pgAdmin.Browser.docker?.query_tool_workspace;
  const defaultDocker = pgAdmin.Browser.docker?.default_workspace;
  const owner = [docker, defaultDocker].find((d)=>d?.find?.(panelId));

  if(!owner) {
    /* Closed since; forget it and let a new panel be opened. */
    reusablePanels.delete(dbKey);
    return false;
  }

  owner.focus(panelId);
  pgAdmin.Browser.Events.trigger(
    DBL_CLICK_RUN_QUERY, transId, sql, autoRun
  );
  return true;
}

/* Open a new Query Tool panel carrying the SQL, and remember it for reuse.
 * The SQL travels through localStorage under sql_id, the mechanism the ERD
 * and Schema Diff tools already use to seed a Query Tool. */
function openNewPanel(sqlEditorMod, parentData, title, sql, autoRun, dbKey) {
  const transId = getRandomInt(1, 9999999);
  const sqlId = `dblclick${transId}`;
  localStorage.setItem(sqlId, sql);

  let panelUrl = url_for('sqleditor.panel', {'trans_id': transId})
    + `?is_query_tool=${true}`
    + `&sgid=${parentData.server_group._id}`
    + `&sid=${parentData.server._id}`
    + `&did=${parentData.database._id}`
    + `&sql_id=${sqlId}`;

  if(parentData.database._label) {
    panelUrl += `&database_name=${encodeURIComponent(parentData.database._label)}`;
  }
  if(!parentData.server.username && parentData.server.user?.name) {
    panelUrl += `&user=${encodeURIComponent(parentData.server.user.name)}`;
  }

  const launched = sqlEditorMod.launch(
    transId, panelUrl, true, title, {dbl_click_auto_run: autoRun}
  );

  /* Only remember panels that live in this window's docker. With 'Open in
   * new browser tab' set for the Query Tool, the panel goes to a window of
   * its own, where neither docker.find() nor the browser event bus reaches
   * it; recording it would just mean a stale entry to step over later. */
  if(launched && !opensInNewBrowserTab()) {
    reusablePanels.set(dbKey, transId);
  }
  return launched;
}

/* Forget a panel once it closes, so its id is not handed out again. The
 * comparison is loose on purpose: the id is stored as the number it was
 * generated as, but comes back from the panel's params as a string. */
export function forgetPanel(transId) {
  for(const [key, value] of reusablePanels.entries()) {
    if(String(value) === String(transId)) {
      reusablePanels.delete(key);
      return;
    }
  }
}

export function clearPanels() {
  reusablePanels.clear();
}

/* Test seam: record a panel without going through the docker. */
export function rememberPanel(dbKey, transId) {
  reusablePanels.set(dbKey, transId);
}

export function rememberedPanel(dbKey) {
  return reusablePanels.get(dbKey);
}

/* The CREATE script for a non-selectable object, fetched from the same
 * endpoint the 'CREATE Script' menu uses. */
async function fetchCreateScript(node, treeItem, nodeData) {
  const sqlUrl = node.generate_url(treeItem, 'sql', nodeData, true);
  const {data} = await getApiInstance().get(sqlUrl);
  return data;
}

export async function handleDoubleClick(treeItem) {
  if(!isEnabled()) {
    return false;
  }

  const tree = pgAdmin.Browser.tree;
  const nodeData = treeItem ? tree.itemData(treeItem) : null;
  const node = nodeData ? pgAdmin.Browser.Nodes[nodeData._type] : null;

  if(!shouldHandleNode(nodeData, node)) {
    return false;
  }

  const parentData = tree.getTreeNodeHierarchy(treeItem);
  const panelKey = panelKeyFor(parentData, nodeData);
  if(!panelKey) {
    /* No database in the hierarchy - a server-level object, say - so there
     * is nothing to run the SQL against. */
    return false;
  }

  const sqlEditorMod = pgAdmin.Tools.SQLEditor;
  const isSelectable = SELECTABLE_NODES.includes(nodeData._type);
  let sql;

  try {
    if(isSelectable) {
      sql = buildSelectSql(
        getSchemaName(parentData), nodeData._label ?? nodeData.label,
        getRowLimit()
      );
    } else {
      sql = await fetchCreateScript(node, treeItem, nodeData);
    }
  } catch (error) {
    pgAdmin.Browser.notifier.pgRespErrorNotify(error);
    return false;
  }

  if(_.isEmpty(sql)) {
    return false;
  }

  /* Name the tab after the object, not the connection: a tab per table is
   * only useful if its title says which table. The schema qualifies it,
   * since the same table name occurs in several schemas. */
  const objectName = nodeData._label ?? nodeData.label;
  const schemaName = getSchemaName(parentData);
  const title = schemaName ? `${schemaName}.${objectName}` : objectName;

  if(reuseExistingPanel(panelKey, sql, isSelectable)) {
    return true;
  }
  return openNewPanel(
    sqlEditorMod, parentData, title, sql, isSelectable, panelKey
  );
}

/* Registered by the Query Tool panel so a reused tab can be told to swap in
 * new SQL and, for a SELECT, run it. */
export function registerRunQueryListener(transId, eventBus) {
  return pgAdmin.Browser.Events.on(
    DBL_CLICK_RUN_QUERY, (targetTransId, sql, autoRun)=>{
      if(String(targetTransId) !== String(transId)) {
        return;
      }
      eventBus.fireEvent(QUERY_TOOL_EVENTS.EDITOR_SET_SQL, sql);
      if(autoRun) {
        eventBus.fireEvent(QUERY_TOOL_EVENTS.EXECUTION_START, sql, {});
      }
    }
  );
}
