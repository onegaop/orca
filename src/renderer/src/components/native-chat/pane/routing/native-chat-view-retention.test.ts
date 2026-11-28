import { describe, expect, it } from 'vitest'
import { chatViewRetention } from './native-chat-view-retention'

const retained = (ids: readonly string[]): string[] =>
  chatViewRetention.retainedAmong(new Set(ids)).split('\n').filter(Boolean)

describe('chatViewRetention', () => {
  it('keeps only the shown chats mounted, however many were visited', () => {
    const ids = Array.from({ length: 50 }, (_, index) => `tab-${String(index).padStart(2, '0')}`)
    for (const id of ids) {
      chatViewRetention.show('layer-a', [id])
    }
    expect(retained(ids)).toEqual(['tab-49'])

    chatViewRetention.show('layer-b', ['other'])
    expect(retained([...ids, 'other'])).toEqual(['other', 'tab-49'])
    chatViewRetention.show('layer-a', [])
    expect(retained([...ids, 'other'])).toEqual(['other'])
    chatViewRetention.show('layer-b', [])
  })

  it('keeps an unfinished annotation through a workspace switch until its editor closes', () => {
    const release = chatViewRetention.holdAnnotation('annotating')
    try {
      chatViewRetention.show('layer-a', ['annotating'])
      chatViewRetention.show('layer-a', [])
      chatViewRetention.show('layer-b', ['other'])
      expect(retained(['annotating', 'other'])).toEqual(['annotating', 'other'])
    } finally {
      release()
      chatViewRetention.show('layer-b', [])
    }
    expect(retained(['annotating', 'other'])).toEqual([])
  })
})
