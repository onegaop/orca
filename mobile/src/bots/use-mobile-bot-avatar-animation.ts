import { useQuery } from '@tanstack/react-query'
import * as z from 'zod'
import { sanitizeAvatarPackAnimation } from '../../../src/shared/bots/avatar-packs/avatar-pack-svg'
import type {
  AvatarAnimationState,
  AvatarPackAnimationResponse
} from '../../../src/shared/bots/avatar-packs/avatar-pack-types'
import { bindDeferredRpcOperation, defineRpcOperation } from '../transport/rpc/rpc-operation'
import { rpcResultVariant } from '../transport/rpc/rpc-operation-result-reader'
import { useBotAvatarHost } from './bot-avatar-uploads'
import { useHostBotStatus } from './host-bot-store'
import type { MobileBotAvatarSource } from './host-bot-row-facts'

const readAnimation = bindDeferredRpcOperation(
  defineRpcOperation({
    name: 'bots.avatar.animation',
    method: 'bots.avatar.animation',
    acceptance: 'object-result-or-null',
    barrier: 'after-caller-barrier',
    read: rpcResultVariant(
      'bot-avatar-animation',
      z
        .object({
          animation: z.unknown(),
          textures: z.record(z.string(), z.string().regex(/^data:image\/(?:webp|png);base64,/i))
        })
        .nullable()
    )
  })
)

export function useMobileBotAvatarAnimation(
  avatar: Extract<MobileBotAvatarSource, { kind: 'avatar-pack' }>
): AvatarPackAnimationResponse | null | undefined {
  const host = useBotAvatarHost(avatar.botId)
  const status = useHostBotStatus(avatar.botId)
  const state: AvatarAnimationState =
    avatar.paused || status === 'inactive'
      ? 'asleep'
      : status === 'permission'
        ? 'help'
        : status === 'working'
          ? 'think'
          : 'idle'
  const { data } = useQuery({
    queryKey: ['bot-avatar-animation', host?.key, avatar.botId, avatar.avatar, state],
    enabled: host !== undefined,
    retry: false,
    staleTime: 60_000,
    gcTime: 60_000,
    queryFn: async () => {
      if (!host) {
        return null
      }
      const result = readAnimation.interpret(
        await readAnimation.request(host.client, { botId: avatar.botId, state })
      )
      const animation = result && sanitizeAvatarPackAnimation(result.animation)
      return result && animation ? { animation, textures: result.textures } : null
    }
  })
  return data
}
