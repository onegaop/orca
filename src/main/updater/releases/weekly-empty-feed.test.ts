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
  fetch.mockResolvedValueOnce(
    new Response('<feed xmlns="http://www.w3.org/2005/Atom"></feed>', {
      headers: { 'content-type': 'application/atom+xml; charset=utf-8' }
    })
  )
  fetch.mockResolvedValueOnce(new Response(null, { status: 403 }))
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

test('an unusable Atom endpoint can be confirmed empty by the public list API', async () => {
  vi.stubGlobal('ORCA_WEEKLY_RELEASE', true)
  fetch.mockResolvedValueOnce(new Response('proxy error', { status: 502 }))
  fetch.mockResolvedValueOnce(Response.json([]))
  const { fetchNewerReleaseTagsWithReadiness } = await import('./updater-prerelease-feed')
  expect(await fetchNewerReleaseTagsWithReadiness('1.4.280', 1)).toEqual({
    tags: [],
    state: 'no-newer'
  })
})
