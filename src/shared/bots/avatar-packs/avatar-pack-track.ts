import type { AvatarKeyframedNode } from './avatar-pack-types'

export function evaluateAvatarAnimationTrack(
  track: NonNullable<AvatarKeyframedNode['tracks']>[string],
  t: number
): number | string | number[] | null {
  const { times, values, discrete } = track
  if (!times || times.length === 0) {
    return null
  }
  if (times.length === 1 || t <= times[0]!) {
    return values[0] ?? null
  }
  if (t >= times.at(-1)!) {
    return values.at(-1) ?? null
  }

  let low = 0
  let high = times.length - 1
  while (low <= high) {
    const mid = (low + high) >> 1
    if (times[mid]! <= t) {
      low = mid + 1
    } else {
      high = mid - 1
    }
  }

  const i0 = Math.max(0, low - 1)
  const i1 = Math.min(times.length - 1, low)

  if (discrete || i0 === i1) {
    return values[i0] ?? null
  }

  const t0 = times[i0]!
  const t1 = times[i1]!
  const alpha = (t - t0) / (t1 - t0)
  const v0 = values[i0]
  const v1 = values[i1]

  if (Array.isArray(v0) && Array.isArray(v1)) {
    const res: number[] = []
    for (let k = 0; k < v0.length; k++) {
      const start = Number(v0[k]) || 0
      const end = Number(v1[k]) || 0
      res.push(start + alpha * (end - start))
    }
    return res
  }
  if (typeof v0 === 'number' && typeof v1 === 'number') {
    return v0 + alpha * (v1 - v0)
  }
  return v0 ?? null
}
