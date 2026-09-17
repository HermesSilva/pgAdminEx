/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import {
  quoteIdent, buildSelectSql, getSchemaName, shouldHandleNode, panelKeyFor,
  forgetPanel, clearPanels, rememberPanel, rememberedPanel, SELECTABLE_NODES,
} from 'pgadmin.tools.sqleditor/dbl_click_query_tool';

describe('dbl_click_query_tool: quoteIdent', ()=>{
  it('quotes a plain identifier', ()=>{
    expect(quoteIdent('actor')).toEqual('"actor"');
  });

  it('preserves case and spaces', ()=>{
    expect(quoteIdent('My Table')).toEqual('"My Table"');
  });

  /* The object name comes from the database and a user with CREATE rights
   * chooses it freely. Since this SQL is assembled in the client rather than
   * by the usual server-side templates, an embedded quote must not be able
   * to close the identifier and append SQL of its own. */
  it('doubles an embedded quote so the identifier cannot be escaped', ()=>{
    expect(quoteIdent('ev"il')).toEqual('"ev""il"');
  });

  it('neutralises a name that tries to append a statement', ()=>{
    const attack = 'a"; DROP TABLE users; --';
    expect(quoteIdent(attack)).toEqual('"a""; DROP TABLE users; --"');
  });

  it('copes with a name that is only quotes', ()=>{
    expect(quoteIdent('""')).toEqual('""""""');
  });
});

describe('dbl_click_query_tool: buildSelectSql', ()=>{
  it('qualifies the object with its schema and applies the limit', ()=>{
    expect(buildSelectSql('public', 'actor', 1000))
      .toEqual('SELECT * FROM "public"."actor"\n\tLIMIT 1000;');
  });

  it('omits the schema when there is none', ()=>{
    expect(buildSelectSql(null, 'actor', 100))
      .toEqual('SELECT * FROM "actor"\n\tLIMIT 100;');
  });

  it('quotes both parts of the qualified name', ()=>{
    expect(buildSelectSql('My Schema', 'My Table', 10))
      .toEqual('SELECT * FROM "My Schema"."My Table"\n\tLIMIT 10;');
  });

  /* The limit reaches this from a preference, so it must not be able to
   * carry arbitrary text into the statement. */
  it('coerces the limit to an integer', ()=>{
    expect(buildSelectSql('public', 'actor', '50; DROP TABLE users'))
      .toEqual('SELECT * FROM "public"."actor"\n\tLIMIT 50;');
  });
});

describe('dbl_click_query_tool: getSchemaName', ()=>{
  it('prefers the schema', ()=>{
    expect(getSchemaName({schema: {_label: 'public'}})).toEqual('public');
  });

  it('falls back to the catalog', ()=>{
    expect(getSchemaName({catalog: {_label: 'pg_catalog'}}))
      .toEqual('pg_catalog');
  });

  /* A partition hangs off a view in the hierarchy. */
  it('falls back to the view', ()=>{
    expect(getSchemaName({view: {_label: 'myview'}})).toEqual('myview');
  });

  it('returns null when there is no namespace', ()=>{
    expect(getSchemaName({})).toBeNull();
    expect(getSchemaName(null)).toBeNull();
  });
});

describe('dbl_click_query_tool: shouldHandleNode', ()=>{
  it.each(SELECTABLE_NODES)('handles the %s node', (type)=>{
    expect(shouldHandleNode({_type: type}, {})).toBe(true);
  });

  /* Collection nodes are how the tree is navigated; double-click must keep
   * expanding them rather than opening a tool. */
  it('leaves collection nodes to the tree', ()=>{
    expect(shouldHandleNode({_type: 'coll-table'}, {})).toBe(false);
    expect(shouldHandleNode({_type: 'coll-function'}, {})).toBe(false);
  });

  it('handles a scriptable node such as a function', ()=>{
    expect(shouldHandleNode(
      {_type: 'function'}, {hasScriptTypes: ['create', 'exec']}
    )).toBe(true);
  });

  it('ignores a node that has no CREATE script', ()=>{
    expect(shouldHandleNode({_type: 'server'}, {hasScriptTypes: []}))
      .toBe(false);
    expect(shouldHandleNode({_type: 'whatever'}, {})).toBe(false);
  });

  it('ignores a missing node or type', ()=>{
    expect(shouldHandleNode(null, {})).toBe(false);
    expect(shouldHandleNode({}, {})).toBe(false);
  });
});

describe('dbl_click_query_tool: panelKeyFor', ()=>{
  const parent = {server: {_id: 1}, database: {_id: 5}};

  /* One tab per object: double-clicking a second table must not be handed
   * to the first table's tab, which was the reported bug. */
  it('gives different objects different keys', ()=>{
    const a = panelKeyFor(parent, {_type: 'table', _id: 10});
    const b = panelKeyFor(parent, {_type: 'table', _id: 11});
    expect(a).not.toEqual(b);
  });

  it('gives the same object the same key, so its tab is reused', ()=>{
    expect(panelKeyFor(parent, {_type: 'table', _id: 10}))
      .toEqual(panelKeyFor(parent, {_type: 'table', _id: 10}));
  });

  /* Ids repeat across servers and databases, so both belong in the key -
   * otherwise a query could land in a panel connected elsewhere. */
  it('separates the same id on different servers', ()=>{
    expect(panelKeyFor(parent, {_type: 'table', _id: 10}))
      .not.toEqual(panelKeyFor(
        {server: {_id: 2}, database: {_id: 5}}, {_type: 'table', _id: 10}
      ));
  });

  it('separates the same id in different databases', ()=>{
    expect(panelKeyFor(parent, {_type: 'table', _id: 10}))
      .not.toEqual(panelKeyFor(
        {server: {_id: 1}, database: {_id: 6}}, {_type: 'table', _id: 10}
      ));
  });

  /* A table and a view can share an id; the type keeps them apart. */
  it('separates objects of different types', ()=>{
    expect(panelKeyFor(parent, {_type: 'table', _id: 10}))
      .not.toEqual(panelKeyFor(parent, {_type: 'view', _id: 10}));
  });

  it('is null without a database or an object', ()=>{
    expect(panelKeyFor({server: {_id: 1}}, {_type: 'table', _id: 1}))
      .toBeNull();
    expect(panelKeyFor(parent, {_type: 'table'})).toBeNull();
    expect(panelKeyFor(parent, null)).toBeNull();
    expect(panelKeyFor(null, {_type: 'table', _id: 1})).toBeNull();
  });

  /* An id of 0 is a real id, not a missing one. */
  it('accepts a zero id', ()=>{
    expect(panelKeyFor(parent, {_type: 'table', _id: 0})).not.toBeNull();
  });
});

describe('dbl_click_query_tool: panel bookkeeping', ()=>{
  beforeEach(()=>clearPanels());
  afterEach(()=>clearPanels());

  it('remembers a panel per database', ()=>{
    rememberPanel('1/5', 4242);
    expect(rememberedPanel('1/5')).toEqual(4242);
    expect(rememberedPanel('1/6')).toBeUndefined();
  });

  /* The id is stored as the number it was generated as, but the panel hands
   * it back as a string from its params; a strict comparison would leave the
   * entry behind and a later double-click would target a closed tab. */
  it('forgets a panel given its id as a string', ()=>{
    rememberPanel('1/5', 4242);
    forgetPanel('4242');
    expect(rememberedPanel('1/5')).toBeUndefined();
  });

  it('forgets a panel given its id as a number', ()=>{
    rememberPanel('1/5', 4242);
    forgetPanel(4242);
    expect(rememberedPanel('1/5')).toBeUndefined();
  });

  it('leaves other databases alone when forgetting one', ()=>{
    rememberPanel('1/5', 1);
    rememberPanel('1/6', 2);
    forgetPanel(1);
    expect(rememberedPanel('1/5')).toBeUndefined();
    expect(rememberedPanel('1/6')).toEqual(2);
  });
});
