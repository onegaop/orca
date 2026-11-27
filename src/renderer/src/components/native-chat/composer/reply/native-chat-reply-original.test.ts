// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
import { nativeChatReplyRevealId } from './native-chat-reply-original'
import { nativeChatReplyQuoteOf, withNativeChatReplyContext } from './native-chat-reply-quote'

const quoted = '> Replying to the earlier message from Codex:\n> Done.\n\nWhich one?'
const original = {
  id: 'first',
  role: 'assistant' as const,
  blocks: [{ type: 'text' as const, text: 'Done.' }]
}

beforeEach(() => {
  localStorage.clear()
  vi.resetModules()
})

it('round-trips a multiline excerpt and preserves the reply body’s own whitespace', () => {
  const sent = withNativeChatReplyContext(
    '    first()\r\n    second()',
    { author: 'agent', excerpt: 'Changed the buttons.\n\nTry again.' },
    'Codex'
  )
  expect(sent).toBe(
    '> Replying to the earlier message from Codex:\n> Changed the buttons.\n>\n> Try again.\n\n    first()\r\n    second()'
  )
  expect(nativeChatReplyQuoteOf(sent)).toEqual({
    author: 'agent',
    label: 'Codex',
    excerpt: 'Changed the buttons.\n\nTry again.',
    rest: '    first()\r\n    second()'
  })
})

it('recovers the exact original in its own chat after reloading and fences ambiguous replies', async () => {
  const { rememberNativeChatReplySource } = await import('./native-chat-reply-sources')
  rememberNativeChatReplySource('conversation-a', quoted, 'first')
  rememberNativeChatReplySource('conversation-a', quoted, 'second')
  rememberNativeChatReplySource('conversation-b', quoted, 'first')

  vi.resetModules()
  const { nativeChatReplyTargetFromSentText } = await import('./native-chat-reply-target')
  const visible = (id: string): boolean => id === original.id
  const storedA = nativeChatReplyTargetFromSentText(quoted, 'conversation-a').target!
  const storedB = nativeChatReplyTargetFromSentText(quoted, 'conversation-b').target!
  const unseen = nativeChatReplyTargetFromSentText(quoted, 'conversation-c').target!

  expect(nativeChatReplyRevealId(storedA, visible, () => [original])).toBeNull()
  expect(storedB.messageId).toBe('first')
  expect(unseen.messageId).toBe('')
})

it('does not restore a refused send’s reply after the user cancelled a newer reply', async () => {
  const {
    cancelNativeChatReplyTarget,
    nativeChatReplyCustody,
    readNativeChatReplyTarget,
    restoreNativeChatReplyTarget,
    setNativeChatReplyTarget,
    settleNativeChatReplySend
  } = await import('./native-chat-reply-target')
  const first = { id: 'reply-a', messageId: 'first', author: 'agent' as const, excerpt: 'Done.' }
  const second = { ...first, id: 'reply-b', messageId: 'second' }
  const scope = 'conversation-a'
  setNativeChatReplyTarget(scope, first)
  expect(settleNativeChatReplySend(scope, first.id)).toBe(true)
  const takenAt = nativeChatReplyCustody(scope)
  setNativeChatReplyTarget(scope, second)
  cancelNativeChatReplyTarget(scope)

  expect(restoreNativeChatReplyTarget(scope, first, takenAt)).toBe(false)
  expect(readNativeChatReplyTarget(scope)).toBeNull()
})
