import { AnimatedBotAvatarRenderer } from '../../../src/shared/bots/avatar-packs/AnimatedBotAvatarRenderer'
import type { MobileBotAvatarAnimationProps } from './MobileBotAvatarAnimation'
import { useMobileBotAvatarAnimation } from './use-mobile-bot-avatar-animation'

export default function MobileBotAvatarAnimationView({
  avatar,
  size,
  borderRadius,
  fallback
}: MobileBotAvatarAnimationProps) {
  const data = useMobileBotAvatarAnimation(avatar)
  return data ? (
    <AnimatedBotAvatarRenderer
      animation={data.animation}
      textures={data.textures}
      style={{ width: size, height: size, borderRadius, flexShrink: 0 }}
    />
  ) : (
    fallback
  )
}
