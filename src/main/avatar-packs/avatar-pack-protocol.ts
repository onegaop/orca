import { extname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { homedir } from 'node:os'
import { promises as fs } from 'node:fs'
import { getAppEnvironment } from '../../shared/app-lifecycle/app-environment'
import type { GlobalSettings } from '../../shared/settings/global-settings-types'
import { avatarPackAssetRelativePath } from '../../shared/avatar-pack-scheme'
import { expandLeadingHomePath } from '../filesystem/home-path-expansion'
import {
  FileTooLargeError,
  openLocalRegularFile,
  readLocalFileBounded
} from '../filesystem/local-file-io/local-regular-file-read'

const MIME_MAP: Record<string, string> = {
  '.json': 'application/json',
  '.webp': 'image/webp',
  '.png': 'image/png'
}

export type AvatarPacksResolveOptions = {
  getSettings?: () => Pick<GlobalSettings, 'avatarPacksDir'> | null | undefined
  env?: NodeJS.ProcessEnv
  homeDir?: string
  userDataDir?: string
  bypassCache?: boolean
}

let cachedPacksDir: { key: string; dir: string } | null = null

export function resetAvatarPacksDirCache(): void {
  cachedPacksDir = null
}

function isStrictlyInsideDir(parentDir: string, targetPath: string): boolean {
  const relPath = relative(parentDir, targetPath)
  if (!relPath || relPath.startsWith('..') || isAbsolute(relPath)) {
    return false
  }
  const prefix = parentDir.endsWith(sep) ? parentDir : `${parentDir}${sep}`
  return targetPath.startsWith(prefix)
}

export async function resolveAvatarPacksDir(
  options?: AvatarPacksResolveOptions
): Promise<string | null> {
  const home = options?.homeDir ?? homedir()
  const env = options?.env ?? process.env
  const userData = options?.userDataDir ?? getAppEnvironment().getPath('userData')
  const getSettings = options?.getSettings
  const customDir = getSettings?.()?.avatarPacksDir?.trim() ?? ''
  const envAvatarPacksDir = env.ORCA_AVATAR_PACKS_DIR?.trim() ?? ''

  const cacheKey = [customDir, envAvatarPacksDir, home, userData].join('\0')
  if (!options?.bypassCache && cachedPacksDir && cachedPacksDir.key === cacheKey) {
    try {
      const stat = await fs.stat(join(cachedPacksDir.dir, 'catalog_index.json'))
      if (stat.isFile()) {
        return cachedPacksDir.dir
      }
    } catch {
      // Cached path is no longer valid; fall through to re-resolve.
    }
    cachedPacksDir = null
  }

  const candidates: string[] = []
  if (customDir) {
    candidates.push(expandLeadingHomePath(customDir, home))
  }
  if (envAvatarPacksDir) {
    candidates.push(expandLeadingHomePath(envAvatarPacksDir, home))
  }
  candidates.push(join(home, '.orca', 'avatar-packs'), join(userData, 'avatar-packs'))

  for (const dir of candidates) {
    try {
      const stat = await fs.stat(join(dir, 'catalog_index.json'))
      if (stat.isFile()) {
        cachedPacksDir = { key: cacheKey, dir }
        return dir
      }
    } catch {
      // Try next candidate.
    }
  }

  return null
}

export async function handleAvatarPackAssetRequest(
  request: Pick<Request, 'method' | 'url'>,
  options?: AvatarPacksResolveOptions,
  limit = 16 * 1024 * 1024
): Promise<Response> {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response(null, { status: 405 })
  }

  const rawRel = avatarPackAssetRelativePath(request.url)
  if (!rawRel) {
    return new Response(null, { status: 400 })
  }

  let decodedRel: string
  try {
    decodedRel = decodeURIComponent(rawRel)
  } catch {
    return new Response(null, { status: 400 })
  }

  if (!decodedRel || decodedRel.includes('\0')) {
    return new Response(null, { status: 400 })
  }

  if (decodedRel.startsWith('/') || decodedRel.startsWith('\\') || isAbsolute(decodedRel)) {
    return new Response(null, { status: 403 })
  }

  if (
    decodedRel !== 'catalog_index.json' &&
    !/^packs\/[A-Za-z0-9_-]+\/(?:animations_json\/[A-Za-z0-9_.-]+\.json|textures\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\.(?:png|webp))$/.test(
      decodedRel
    )
  ) {
    return new Response(null, { status: 403 })
  }

  const root = await resolveAvatarPacksDir({
    ...options,
    bypassCache: options?.bypassCache ?? decodedRel === 'catalog_index.json'
  })
  if (!root) {
    return new Response(JSON.stringify({ error: 'Avatar packs directory not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  const resolvedRoot = resolve(root)
  const fullPath = resolve(resolvedRoot, decodedRel)
  if (!isStrictlyInsideDir(resolvedRoot, fullPath)) {
    return new Response(null, { status: 403 })
  }

  let realRoot: string
  let realPath: string
  try {
    realRoot = await fs.realpath(resolvedRoot)
    realPath = await fs.realpath(fullPath)
  } catch {
    return new Response(null, { status: 404 })
  }

  if (!isStrictlyInsideDir(realRoot, realPath)) {
    return new Response(null, { status: 403 })
  }

  const mimeType = MIME_MAP[extname(realPath).toLowerCase()]
  if (!mimeType) {
    return new Response(null, { status: 403 })
  }
  try {
    const { handle, stats } = await openLocalRegularFile(realPath)
    try {
      if (stats.size > limit) {
        return new Response(null, { status: 413 })
      }
      const data =
        request.method === 'HEAD' ? null : await readLocalFileBounded(handle, limit, stats.size)
      return new Response(data ? new Uint8Array(data) : null, {
        status: 200,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': String(data?.byteLength ?? stats.size),
          'Cache-Control': 'no-cache',
          'Access-Control-Allow-Origin': '*',
          'X-Content-Type-Options': 'nosniff',
          'Content-Security-Policy': "default-src 'none'; sandbox"
        }
      })
    } finally {
      await handle.close()
    }
  } catch (error) {
    return new Response(null, { status: error instanceof FileTooLargeError ? 413 : 404 })
  }
}
