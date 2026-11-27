import { afterEach, expect, test, vi } from 'vitest'

afterEach(() => {
  vi.unstubAllGlobals()
  vi.resetModules()
})

test('all selectable release channels remain on the fork in private builds', async () => {
  vi.stubGlobal('ORCA_WEEKLY_RELEASE', true)
  const {
    MAIN_RELEASE_REPO,
    RELEASE_CHANNELS,
    getReleaseRepoForChannel,
    getReleaseNotesUrlForVersion
  } = await import('./release-channel')
  expect(MAIN_RELEASE_REPO).toBe('stablyai/orca')
  expect(RELEASE_CHANNELS.map(getReleaseRepoForChannel)).toEqual(Array(5).fill('onegaop/orca'))
  expect(getReleaseNotesUrlForVersion('1.4.279')).toBe(
    'https://github.com/onegaop/orca/releases/tag/v1.4.279'
  )
})

test('an ordinary build does not opt in to the fork', async () => {
  vi.stubGlobal('ORCA_WEEKLY_RELEASE', false)
  const { getReleaseRepoForChannel } = await import('./release-channel')
  expect(getReleaseRepoForChannel('stable')).toBe('stablyai/orca')
  expect(getReleaseRepoForChannel('hourly')).toBe('stablyai/orca-hourly')
})
