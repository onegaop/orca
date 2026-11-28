import { lazy, Suspense } from 'react'
import type { MobileBotAvatarAnimationProps } from './MobileBotAvatarAnimation'

const BotAvatarAnimation = lazy(() => import('./MobileBotAvatarAnimationView.web'))

export function MobileBotAvatarAnimation(props: MobileBotAvatarAnimationProps) {
  return (
    <Suspense fallback={props.fallback}>
      <BotAvatarAnimation {...props} />
    </Suspense>
  )
}
