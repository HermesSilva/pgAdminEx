/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import { withTheme } from '../fake_theme';
import CodeMirror from 'sources/components/ReactCodeMirror';
import { executeScriptAtCursor } from 'pgadmin.tools.sqleditor/components/QueryToolConstants';

import { render } from '@testing-library/react';

describe('executeScriptAtCursor', ()=>{
  it('is on when the preference is set', ()=>{
    expect(executeScriptAtCursor({execute_script_at_cursor: true})).toBe(true);
  });

  it('is off when the preference is unset', ()=>{
    expect(executeScriptAtCursor({execute_script_at_cursor: false})).toBe(false);
  });

  /* An older config database has no such preference; Execute script must
   * keep running the whole editor rather than silently narrowing. */
  it('is off when the preference is absent', ()=>{
    expect(executeScriptAtCursor({})).toBe(false);
  });

  it('is off when there are no preferences at all', ()=>{
    expect(executeScriptAtCursor(undefined)).toBe(false);
  });
});

/* Execute script, with the preference on, runs whatever getQueryAt() returns
 * for the cursor position - the same extraction Execute query uses. These
 * pin the blank-line delimiting that behaviour now depends on. */
describe('Execute script at cursor: blank line delimiting', ()=>{
  const ThemedCM = withTheme(CodeMirror);
  let cmInstance, editor;

  const cmRerender = (props)=>{
    cmInstance.rerender(
      <ThemedCM
        value={'Init text'}
        className="testClass"
        currEditor={(obj) => {
          editor = obj;
        }}
        {...props}
      />
    );
  };

  beforeEach(()=>{
    cmInstance = render(
      <ThemedCM
        value={'Init text'}
        className="testClass"
        currEditor={(obj) => {
          editor = obj;
        }}
      />);
  });

  const script = 'select * from public.actor;\n\nselect * from public.city;\n\nselect * from public.address;';

  it('runs only the block the cursor is in, not the whole script', ()=>{
    cmRerender({value: script});
    // Cursor inside the second statement.
    expect(editor.getQueryAt(31).value).toEqual('select * from public.city;');
  });

  it('picks the first block when the cursor is at the top', ()=>{
    cmRerender({value: script});
    expect(editor.getQueryAt(0).value).toEqual('select * from public.actor;');
  });

  it('picks the last block when the cursor is at the end', ()=>{
    cmRerender({value: script});
    expect(editor.getQueryAt(script.length).value)
      .toEqual('select * from public.address;');
  });

  /* A single statement spread over blank lines must not be cut in half: the
   * blank-line boundary is dropped when it would split a Statement node. */
  it('keeps a statement that spans blank lines whole', ()=>{
    const spanning = 'SELECT *\n\nFROM pg_class\n\nWHERE id = 1;';
    cmRerender({value: spanning});
    expect(editor.getQueryAt(10).value).toEqual(spanning);
  });

  it('runs the sole statement when the editor holds just one', ()=>{
    cmRerender({value: 'select * from public.actor;'});
    expect(editor.getQueryAt(5).value).toEqual('select * from public.actor;');
  });
});
