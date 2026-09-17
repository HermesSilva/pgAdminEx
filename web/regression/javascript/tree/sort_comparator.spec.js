/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

/* aspen-core re-sorts a Directory's children with the host's
 * sortComparator on every insertion (aspen-core/src/Directory.ts), so the
 * order the server sent is not preserved on its own and a node's
 * sort_priority has to be honoured here as well as server-side.
 *
 * The comparator lives in tree/ObjectExplorer/index.jsx, inside a
 * component that cannot be mounted without the whole browser, so the
 * ordering rule is reproduced here rather than imported.
 */

const naturalSort = (a, b) => a.localeCompare(b);

/* Mirrors the comparator in ObjectExplorer/index.jsx. */
function sortComparator(a, b) {
  if (a._metadata && a._metadata.data._type == 'column') return 0;

  const aPriority = a._metadata?.data?.sort_priority ?? 0;
  const bPriority = b._metadata?.data?.sort_priority ?? 0;
  if (aPriority !== bPriority) {
    return aPriority - bPriority;
  }

  if (a.constructor === b.constructor) {
    return naturalSort(a.fileName, b.fileName);
  }
  return 0;
}

const node = (label, priority)=>({
  fileName: label,
  _metadata: {
    data: {
      _type: 'coll-x',
      label: label,
      ...(priority === undefined ? {} : {sort_priority: priority}),
    },
  },
});

describe('ObjectExplorer sortComparator', ()=>{
  it('sorts children without a priority alphabetically', ()=>{
    const nodes = [node('Schemas'), node('Casts'), node('Extensions')];
    expect(nodes.sort(sortComparator).map((n)=>n.fileName))
      .toEqual(['Casts', 'Extensions', 'Schemas']);
  });

  /* The Tables shortcut under a database relies on this. */
  it('puts a negative priority ahead of everything else', ()=>{
    const nodes = [
      node('Casts', 0), node('Schemas', 0), node('Tables', -1),
    ];
    expect(nodes.sort(sortComparator).map((n)=>n.fileName))
      .toEqual(['Tables', 'Casts', 'Schemas']);
  });

  it('treats a missing priority as zero', ()=>{
    const nodes = [node('Casts'), node('Tables', -1), node('Aardvark')];
    expect(nodes.sort(sortComparator).map((n)=>n.fileName))
      .toEqual(['Tables', 'Aardvark', 'Casts']);
  });

  it('falls back to the label when priorities are equal', ()=>{
    const nodes = [node('Beta', -1), node('Alpha', -1)];
    expect(nodes.sort(sortComparator).map((n)=>n.fileName))
      .toEqual(['Alpha', 'Beta']);
  });

  /* Reproduces the reported bug: the server sent Tables first, but the
   * comparator re-sorted on the label alone and pushed it to the end. */
  it('keeps Tables first among a real database\'s children', ()=>{
    const nodes = [
      node('Casts'), node('Catalogs'), node('Event Triggers'),
      node('Extensions'), node('Foreign Data Wrappers'), node('Languages'),
      node('Publications'), node('Schemas'), node('Subscriptions'),
      node('Tables', -1),
    ];
    expect(nodes.sort(sortComparator)[0].fileName).toEqual('Tables');
  });
});
