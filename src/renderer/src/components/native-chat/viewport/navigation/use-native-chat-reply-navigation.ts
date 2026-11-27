import { useCallback, useLayoutEffect, type RefObject } from 'react'
import {
  useNativeChatMessageRevealAnswer,
  type NativeChatRevealMessage
} from '../../composer/reply/native-chat-reply-context'
import { nativeChatReplyRevealId } from '../../composer/reply/native-chat-reply-original'
import { nativeChatSlotIndexOf } from '../../conversation/slots/native-chat-transcript-slot-selection'
import type { NativeChatTranscriptSlot } from '../../conversation/slots/native-chat-transcript-slots'

export function useNativeChatReplyNavigation({
  scrollRef,
  slots,
  subagent,
  onReveal
}: {
  scrollRef: RefObject<HTMLDivElement | null>
  slots: readonly NativeChatTranscriptSlot[]
  subagent: boolean
  onReveal: (messageId: string) => void
}): void {
  const revealMessage = useCallback(
    (message: NativeChatRevealMessage, probe: boolean): string | null => {
      const found = nativeChatReplyRevealId(
        message,
        (messageId) => nativeChatSlotIndexOf(slots, messageId) >= 0,
        () => slots.flatMap((slot) => (slot.kind === 'message' ? [slot.message] : []))
      )
      if (found && !probe) {
        onReveal(found)
      }
      return found
    },
    [onReveal, slots]
  )
  useNativeChatMessageRevealAnswer(scrollRef, subagent ? null : revealMessage)
  // The scroller can mount after the transcript, so mark it on every render.
  useLayoutEffect(() => {
    scrollRef.current?.toggleAttribute('data-native-chat-subagent-view', subagent)
  })
}
