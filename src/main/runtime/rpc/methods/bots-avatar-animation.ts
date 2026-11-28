import { parseBotAvatar } from '../../../../shared/bot-avatar'
import { BotAvatarAnimation } from '../../../../shared/rpc-contract/bot-avatar-params'
import { loadMobileAvatarPackAnimation } from '../../../avatar-packs/avatar-pack-mobile-animation'
import { defineMethod } from '../core'

export const BOT_AVATAR_ANIMATION_METHOD = defineMethod({
  name: 'bots.avatar.animation',
  permission: 'workspace',
  params: BotAvatarAnimation,
  handler: async ({ botId, state }, { runtime }) => {
    const bot = runtime.bots.list().find((entry) => entry.id === botId)
    const avatar = parseBotAvatar(bot?.avatar ?? null)
    if (avatar?.kind !== 'avatar-pack') {
      return null
    }
    const settings = runtime.requireStore().getSettings()
    return loadMobileAvatarPackAnimation(avatar, state, { getSettings: () => settings })
  }
})
