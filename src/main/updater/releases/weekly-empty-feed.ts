import { net } from 'electron'
import { MAIN_RELEASE_REPO, WEEKLY_RELEASE_BUILD } from '../../../shared/updater/release-channel'
import { FETCH_TIMEOUT_MS } from './updater-release-readiness'

async function hasNoPublicWeeklyRelease(): Promise<boolean> {
  try {
    const response = await net.fetch(
      `https://api.github.com/repos/${MAIN_RELEASE_REPO}/releases?per_page=1`,
      {
        headers: { Accept: 'application/vnd.github+json' },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)
      }
    )
    if (!response.ok) {
      return false
    }
    const releases: unknown = await response.json()
    return Array.isArray(releases) && releases.length === 0
  } catch {
    return false
  }
}

export function shouldSkipStableFallback(result: { state: string }): boolean {
  return WEEKLY_RELEASE_BUILD && result.state === 'no-newer'
}

export async function confirmEmptyWeeklyFeed<T>(atom: T[] | null): Promise<T[] | null> {
  if (!WEEKLY_RELEASE_BUILD || atom?.length) {
    return atom
  }
  return (await hasNoPublicWeeklyRelease()) ? [] : null
}
