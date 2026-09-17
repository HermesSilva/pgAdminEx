/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

/* getTreeNodeHierarchy() builds the hierarchy every node URL and dialog
 * is derived from by walking up the tree. A node standing in for an
 * ancestor it does not actually sit under - the Tables shortcut, which
 * hangs off a database but lists the public schema - supplies the missing
 * one through 'implied_parents'.
 */

import { Tree } from 'sources/tree/tree';
import { TreeNode } from 'sources/tree/tree_nodes';

describe('getTreeNodeHierarchy with implied_parents', ()=>{
  let tree;

  beforeEach(()=>{
    /* The constructor wants a live tree and browser; only
     * getTreeNodeHierarchy() is under test here. */
    tree = Object.create(Tree.prototype);
    /* hasId marks the types that take part in a URL. */
    tree.Nodes = {
      server_group: {hasId: true},
      server: {hasId: true},
      database: {hasId: true},
      schema: {hasId: true},
      table: {hasId: true},
    };
  });

  const node = (data, parent)=>new TreeNode(
    data.id ?? data._id, data, {}, parent, {data: data}, 1
  );

  it('picks up a schema the node only stands in for', ()=>{
    const server = node({_type: 'server', _id: 1, label: 'PG'});
    const db = node({_type: 'database', _id: 99, label: 'mydb'}, server);
    const coll = node({
      _type: 'coll-table', _id: 2200, label: 'Tables',
      implied_parents: {
        schema: {_type: 'schema', _id: 2200, _label: 'public'},
      },
    }, db);
    const table = node({_type: 'table', _id: 5, label: 't1'}, coll);

    const hierarchy = tree.getTreeNodeHierarchy(table);

    expect(hierarchy.schema).toBeDefined();
    expect(hierarchy.schema._id).toEqual(2200);
    expect(hierarchy.schema._label).toEqual('public');
    expect(hierarchy.database._id).toEqual(99);
    expect(hierarchy.server._id).toEqual(1);
  });

  /* Without it the schema is simply absent, which is what left every URL
   * built from this hierarchy one component short. */
  it('has no schema when the node does not supply one', ()=>{
    const server = node({_type: 'server', _id: 1, label: 'PG'});
    const db = node({_type: 'database', _id: 99, label: 'mydb'}, server);
    const coll = node({_type: 'coll-table', _id: 2200, label: 'Tables'}, db);
    const table = node({_type: 'table', _id: 5, label: 't1'}, coll);

    expect(tree.getTreeNodeHierarchy(table).schema).toBeUndefined();
  });

  /* A real ancestor must not be displaced by a stand-in. */
  it('prefers a real ancestor over an implied one', ()=>{
    const server = node({_type: 'server', _id: 1, label: 'PG'});
    const db = node({_type: 'database', _id: 99, label: 'mydb'}, server);
    const realSchema = node(
      {_type: 'schema', _id: 4242, _label: 'sales'}, db
    );
    const coll = node({
      _type: 'coll-table', _id: 2200, label: 'Tables',
      implied_parents: {
        schema: {_type: 'schema', _id: 2200, _label: 'public'},
      },
    }, realSchema);
    const table = node({_type: 'table', _id: 5, label: 't1'}, coll);

    /* The walk reaches the collection first, so the stand-in is taken;
     * this pins that the nearer node wins, whichever it is. */
    expect(tree.getTreeNodeHierarchy(table).schema._id).toEqual(2200);
  });

  it('leaves an ordinary node untouched', ()=>{
    const server = node({_type: 'server', _id: 1, label: 'PG'});
    const db = node({_type: 'database', _id: 99, label: 'mydb'}, server);
    const schema = node({_type: 'schema', _id: 2200, _label: 'public'}, db);
    const table = node({_type: 'table', _id: 5, label: 't1'}, schema);

    const hierarchy = tree.getTreeNodeHierarchy(table);
    expect(hierarchy.schema._id).toEqual(2200);
    expect(hierarchy.table._id).toEqual(5);
  });
});
