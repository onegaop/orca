import { expect, it } from 'vitest'
import { chatViewRetention } from './native-chat-view-retention'

it('evicts old views across workspaces and preserves an unfinished annotation until it closes', () => {
  const tabs = new Set(['a', 'b', 'c', 'd', 'e', 'split'])
  chatViewRetention.show('first', ['a', 'split'])
  const release = chatViewRetention.hold('a', 'annotation')
  try {
    chatViewRetention.show('first', ['b', 'split'])
    chatViewRetention.show('first', ['c', 'split'])
    chatViewRetention.show('first', ['d', 'split'])
    chatViewRetention.show('first', ['e', 'split'])
    chatViewRetention.show('second', ['a'])
    expect(chatViewRetention.retainedAmong(tabs)).toBe('a\nb\nc\nd\ne\nsplit')
    chatViewRetention.show('second', [])
    expect(chatViewRetention.retainedAmong(tabs)).toBe('a\nc\nd\ne\nsplit')
    chatViewRetention.show('first', ['b', 'split'])
    expect(chatViewRetention.retainedAmong(tabs)).toBe('a\nb\nd\ne\nsplit')
    chatViewRetention.show('first', ['c', 'split'])
    chatViewRetention.show('first', ['d', 'split'])
    chatViewRetention.show('first', ['e', 'split'])
    expect(chatViewRetention.retainedAmong(tabs)).toBe('a\nb\nc\nd\ne\nsplit')
    release()
    expect(chatViewRetention.retainedAmong(tabs)).toBe('b\nc\nd\ne\nsplit')
  } finally {
    chatViewRetention.show('first', [])
    chatViewRetention.show('second', [])
    chatViewRetention.forget(tabs)
  }
})
