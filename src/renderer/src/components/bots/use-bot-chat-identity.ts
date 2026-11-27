import { useMemo, type ComponentProps } from 'react'
import { isListedBotHost } from '@/lib/bot-hosts'
import { getRuntimeTargetHostId } from '@/runtime/rpc/targets/runtime-client-target'
import type { BotAvatar } from './BotAvatar'
import { useNativeChatTabOwnerWorktreeId } from '../native-chat/pane/ownership/use-native-chat-tab-owner'
import type { NativeChatStructuredViewProps } from '../native-chat/native-chat-view-types'
import { useBots, useBotsEnabled } from '@/lib/bot-catalog'
import { useAppStore } from '@/store'
import type { RuntimeClientTarget } from '../../../../shared/remote-runtime/host-catalog/runtime-client-target'
import { parseWorkspaceKey } from '../../../../shared/workspace/identity/workspace-scope'
import { botOwnsChatSession } from '../../../../shared/bots/bot-chat-identity'
import { selectFolderWorkspaceOnHost } from '../../store/folder-workspaces/folder-workspace-record-index'

export type BotChatIdentity = ComponentProps<typeof BotAvatar>['bot'] & {
  showName?: boolean
}

/** The bot whose chat this is, from the catalog of the host that owns the session. */
export function useBotChatIdentity(
  workspaceId: string | null,
  sessionId: string | null,
  target: RuntimeClientTarget
) {
  const enabled = useBotsEnabled()
  const scope = parseWorkspaceKey(workspaceId ?? '')
  const folderId = scope?.type === 'folder' ? scope.folderWorkspaceId : null
  const hostId = getRuntimeTargetHostId(target)
  const listed = isListedBotHost(hostId)
  const workspace = useAppStore((state) =>
    listed && folderId ? selectFolderWorkspaceOnHost(state, folderId, hostId) : undefined
  )
  const bots = useBots(enabled && workspace !== undefined)
  return (
    bots.find(
      (bot) =>
        bot.hostId === hostId &&
        bot.folderWorkspaceId === workspace?.id &&
        botOwnsChatSession(bot, sessionId, workspace.externalConversations)
    ) ?? null
  )
}

export function useBotChatOwner(
  props: Pick<NativeChatStructuredViewProps, 'tabId' | 'sessionId' | 'target'>
) {
  const ownerWorktreeId = useNativeChatTabOwnerWorktreeId(props.tabId)
  const turnBot = useBotChatIdentity(ownerWorktreeId, props.sessionId, props.target)
  const {
    id,
    hostId,
    name,
    avatar = null,
    avatarColor,
    avatarOutfit,
    folderWorkspaceId,
    paused
  } = turnBot ?? {}
  // Catalog refreshes can replace the Bot object without changing anything shown in the rows.
  const identity = useMemo<BotChatIdentity | null>(
    () =>
      id && hostId && name !== undefined
        ? { id, hostId, name, avatar, avatarColor, avatarOutfit, folderWorkspaceId, paused }
        : null,
    [id, hostId, name, avatar, avatarColor, avatarOutfit, folderWorkspaceId, paused]
  )
  return { ownerWorktreeId, turnBot: identity, bot: turnBot }
}
