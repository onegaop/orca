import { net } from 'electron'
import { UPDATE_RELEASE_REPO, WEEKLY_RELEASE_BUILD } from '../../../shared/updater/release-channel'
import { FETCH_TIMEOUT_MS } from './updater-release-readiness'

async function hasNoPublicWeeklyRelease(): Promise<boolean> {
  try {
    const response = await net.fetch(
      `https://api.github.com/repos/${UPDATE_RELEASE_REPO}/releases?per_page=1`,
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

export function acceptEmptyReleaseAtom(response: Response, body: string): boolean {
  return (
    !WEEKLY_RELEASE_BUILD ||
    (response.headers.get('content-type')?.startsWith('application/atom+xml') === true &&
      /<feed\s[^>]*xmlns=["']http:\/\/www\.w3\.org\/2005\/Atom["']/.test(body))
  )
}

export async function confirmEmptyWeeklyFeed<T>(atom: T[] | null): Promise<T[] | null> {
  if (!WEEKLY_RELEASE_BUILD || atom !== null) {
    return atom
  }
  return (await hasNoPublicWeeklyRelease()) ? [] : null
}
