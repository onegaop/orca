// @vitest-environment happy-dom
import { act, render } from '@testing-library/react'
import { Editor } from '@tiptap/core'
import { createRef } from 'react'
import { expect, it } from 'vitest'
import {
  openNativeChatViewTabs,
  releaseNativeChatViewTabs
} from '../../pane/ownership/native-chat-view-memory'
import type { NativeChatComposerInput } from './native-chat-composer-input'
import {
  NativeChatComposerEditorOwner,
  releaseNativeChatComposerEditors
} from './native-chat-composer-editor-owner'
import { NativeChatPromptEditor } from './NativeChatPromptEditor'

it('preserves selection and undo when evicting an open chat and disposes them on close', async () => {
  const tab = { tabId: 'evicted-composer', worktreeId: 'workspace' }
  const input = createRef<NativeChatComposerInput>()
  const composer = (
    <NativeChatComposerEditorOwner viewTab={tab}>
      <NativeChatPromptEditor
        scopeKey="agent-session:evicted-composer"
        inputRef={input}
        initialValue="hello"
        disabled={false}
        placeholder="Message"
        onChange={() => {}}
        onSelect={() => {}}
      />
    </NativeChatComposerEditorOwner>
  )
  openNativeChatViewTabs([tab.tabId])
  const first = render(composer)
  const editor = Reflect.get(first.getByRole('textbox'), 'editor')
  if (!(editor instanceof Editor)) {
    throw new Error('Expected a mounted composer editor')
  }
  act(() => {
    input.current!.setSelectionRange(5, 5)
    input.current!.insertText?.(' world')
    input.current!.setSelectionRange(2, 4)
  })
  first.unmount()
  await act(() => Promise.resolve())
  const second = render(composer)
  expect(input.current!.value).toBe('hello world')
  expect([input.current!.selectionStart, input.current!.selectionEnd]).toEqual([2, 4])
  act(() => {
    editor.commands.undo()
  })
  expect(input.current!.value).toBe('hello')
  second.unmount()
  await act(() => Promise.resolve())
  let destroyed = false
  editor.on('destroy', () => {
    destroyed = true
  })
  releaseNativeChatComposerEditors([tab.tabId])
  releaseNativeChatViewTabs([tab.tabId])
  expect(destroyed).toBe(true)
})
