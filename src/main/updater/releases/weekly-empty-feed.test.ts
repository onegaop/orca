import { afterEach, expect, test, vi } from 'vitest'

const fetch = vi.hoisted(() => vi.fn())
vi.mock('electron', () => ({ net: { fetch } }))

afterEach(() => {
  fetch.mockReset()
  vi.unstubAllGlobals()
  vi.resetModules()
})

test('a confirmed empty public channel reports no available version', async () => {
  vi.stubGlobal('ORCA_WEEKLY_RELEASE', true)
  fetch.mockResolvedValueOnce(new Response('<feed></feed>'))
  fetch.mockResolvedValueOnce(Response.json([]))
  const { fetchNewerReleaseTagsWithReadiness } = await import('./updater-prerelease-feed')
  const { shouldSkipStableFallback } = await import('./weekly-empty-feed')
  const result = await fetchNewerReleaseTagsWithReadiness('1.4.280', 1)
  expect(result).toEqual({ tags: [], state: 'no-newer' })
  expect(shouldSkipStableFallback(result)).toBe(true)
})

test('failed transport is not mistaken for an empty channel', async () => {
  vi.stubGlobal('ORCA_WEEKLY_RELEASE', true)
  fetch.mockResolvedValueOnce(new Response(null, { status: 503 }))
  fetch.mockResolvedValueOnce(new Response(null, { status: 503 }))
  const { fetchNewerReleaseTagsWithReadiness } = await import('./updater-prerelease-feed')
  const { shouldSkipStableFallback } = await import('./weekly-empty-feed')
  const result = await fetchNewerReleaseTagsWithReadiness('1.4.280', 1)
  expect(result.state).toBe('unavailable')
  expect(shouldSkipStableFallback(result)).toBe(false)
})
