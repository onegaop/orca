import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { AppState, View } from 'react-native'
import Svg from 'react-native-svg'
import type { AvatarKeyframedAnimation } from '../../../src/shared/bots/avatar-packs/avatar-pack-types'
import { useReducedMotionEnabled } from '../platform/accessibility/use-reduced-motion'
import type { MobileBotAvatarSource } from './host-bot-row-facts'
import { prepareNativeAvatarScene, renderNativeAvatarNode } from './native-avatar-pack-scene'
import { useMobileBotAvatarAnimation } from './use-mobile-bot-avatar-animation'

const FRAME_INTERVAL_MS = 1000 / 12

export type MobileBotAvatarAnimationProps = {
  avatar: Extract<MobileBotAvatarSource, { kind: 'avatar-pack' }>
  size: number
  borderRadius: number
  fallback: ReactNode
}

export function MobileBotAvatarAnimation({
  avatar,
  size,
  borderRadius,
  fallback
}: MobileBotAvatarAnimationProps) {
  const data = useMobileBotAvatarAnimation(avatar)
  const scene = useMemo(() => (data ? prepareNativeAvatarScene(data) : null), [data])
  const reduceMotion = useReducedMotionEnabled()
  const progress = useAvatarProgress(scene?.animation, reduceMotion === false)

  if (!scene) {
    return fallback
  }
  return (
    <View
      pointerEvents="none"
      style={{ width: size, height: size, borderRadius, overflow: 'hidden' }}
    >
      <Svg width={size} height={size} viewBox={scene.animation.vb.join(' ')}>
        {scene.nodes.map((node) => renderNativeAvatarNode(node, progress))}
      </Svg>
    </View>
  )
}

function useAvatarProgress(animation: AvatarKeyframedAnimation | undefined, animated: boolean) {
  const [frame, setFrame] = useState<{ animation: AvatarKeyframedAnimation; progress: number }>()

  useEffect(() => {
    if (!animation || !animated) {
      return
    }
    const duration = animation.duration * 1000
    let timer: ReturnType<typeof setInterval> | undefined
    const stop = () => {
      clearInterval(timer)
      timer = undefined
    }
    const start = () => {
      if (timer !== undefined) {
        return
      }
      const started = performance.now()
      timer = setInterval(() => {
        const elapsed = (performance.now() - started) / duration
        setFrame({ animation, progress: animation.once ? Math.min(elapsed, 1) : elapsed % 1 })
        if (animation.once && elapsed >= 1) {
          stop()
        }
      }, FRAME_INTERVAL_MS)
    }
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        start()
      } else {
        stop()
      }
    })
    if (!AppState.currentState || AppState.currentState === 'active') {
      start()
    }
    return () => {
      stop()
      subscription.remove()
    }
  }, [animation, animated])

  return animated && frame?.animation === animation ? (frame?.progress ?? 0) : 0
}
