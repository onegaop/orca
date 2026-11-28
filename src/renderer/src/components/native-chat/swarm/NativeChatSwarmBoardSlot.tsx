import type { RefObject } from 'react'
import type { NativeChatComposerHandle } from '../composer/native-chat-composer-types'
import { NativeChatSwarmBoardPanel } from './NativeChatSwarmBoardPanel'
import type { NativeChatSwarmBoardState } from './use-native-chat-swarm-board'

export function NativeChatSwarmBoardSlot({
  board,
  canMention,
  composerRef,
  focusComposer
}: {
  board?: NativeChatSwarmBoardState | null
  canMention: boolean
  composerRef: RefObject<NativeChatComposerHandle | null>
  focusComposer: () => void
}): React.JSX.Element | null {
  if (!board) {
    return null
  }
  return (
    <NativeChatSwarmBoardPanel
      board={board}
      canMention={canMention}
      onMention={(name) => {
        composerRef.current?.insertTypedText(`@${name} `)
        focusComposer()
      }}
      onCloseFocus={focusComposer}
    />
  )
}
