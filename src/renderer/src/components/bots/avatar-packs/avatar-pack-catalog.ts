import { useEffect, useSyncExternalStore } from 'react'
import { useAppStore } from '@/store'
import { avatarPackAssetUrl } from '../../../../../shared/avatar-pack-scheme'
import {
  getAvatarPackCharacters,
  isAvatarPackCatalogIndex,
  resolveAvatarPackCharacterKey
} from '../../../../../shared/bots/avatar-packs/avatar-pack-catalog-selection'
import { sanitizeAvatarPackAnimation } from './avatar-pack-svg'
import type { AvatarKeyframedAnimation, AvatarPackCatalogIndex } from './avatar-pack-types'

export {
  getAvatarPackCharacters,
  resolveAvatarPackAnimationFile
} from '../../../../../shared/bots/avatar-packs/avatar-pack-catalog-selection'

const MAX_CACHED_ANIMATIONS = 128

let cachedCatalog: AvatarPackCatalogIndex | null = null
let catalogSettled = false
let catalogPromise: Promise<AvatarPackCatalogIndex | null> | null = null
let catalogVersion = 0
let snapshotRevision = 0
let trackedPacksDir: string | undefined

const animationCache = new Map<string, AvatarKeyframedAnimation>()
const listeners = new Set<() => void>()

function emitCatalogChange(): void {
  snapshotRevision += 1
  for (const listener of listeners) {
    listener()
  }
}

function subscribeCatalog(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

function getCatalogSnapshot(): number {
  return snapshotRevision
}

export function invalidateAvatarPackCatalogCache(): void {
  cachedCatalog = null
  catalogSettled = false
  catalogPromise = null
  animationCache.clear()
  catalogVersion += 1
  emitCatalogChange()
}

function settleCatalog(requestVersion: number, next: AvatarPackCatalogIndex | null): void {
  if (requestVersion === catalogVersion) {
    cachedCatalog = next
    catalogSettled = true
    emitCatalogChange()
  }
}

export async function fetchAvatarPackCatalog(): Promise<AvatarPackCatalogIndex | null> {
  if (catalogSettled) {
    return cachedCatalog
  }
  if (catalogPromise) {
    return catalogPromise
  }
  const requestVersion = catalogVersion
  const pending = (async (): Promise<AvatarPackCatalogIndex | null> => {
    try {
      const url = avatarPackAssetUrl('catalog_index.json')
      const resp = await fetch(url, { cache: 'no-store' })
      if (!resp.ok) {
        settleCatalog(requestVersion, null)
        return null
      }
      const raw: unknown = await resp.json()
      const parsed = isAvatarPackCatalogIndex(raw) ? raw : null
      settleCatalog(requestVersion, parsed)
      return parsed
    } catch {
      settleCatalog(requestVersion, null)
      return null
    } finally {
      if (requestVersion === catalogVersion) {
        catalogPromise = null
      }
    }
  })()
  catalogPromise = pending
  return pending
}

export function useAvatarPackCatalog(enabled = true): {
  catalog: AvatarPackCatalogIndex | null
  loading: boolean
  version: number
} {
  const customDir = useAppStore((s) => s.settings?.avatarPacksDir ?? '')
  const version = useSyncExternalStore(subscribeCatalog, getCatalogSnapshot, getCatalogSnapshot)

  useEffect(() => {
    if (trackedPacksDir === undefined) {
      trackedPacksDir = customDir
      return
    }
    if (trackedPacksDir !== customDir) {
      trackedPacksDir = customDir
      invalidateAvatarPackCatalogCache()
    }
  }, [customDir])

  useEffect(() => {
    if (!enabled || catalogSettled) {
      return
    }
    void fetchAvatarPackCatalog()
  }, [enabled, version])

  return {
    catalog: cachedCatalog,
    loading: enabled && !catalogSettled,
    version
  }
}

export function getAvatarPackIds(catalog: AvatarPackCatalogIndex): string[] {
  return Object.keys(catalog).filter((key) => {
    const chars = catalog[key]?.characters
    return Boolean(chars && Object.keys(chars).length > 0)
  })
}

export function formatAvatarPackId(packId: string): string {
  const spaced = packId
    .replace(/([a-z])(\d)/gi, '$1 $2')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/[-_]+/g, ' ')
    .trim()
  if (!spaced) {
    return packId
  }
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase()
}

export function formatAvatarPackLabel(
  catalog: AvatarPackCatalogIndex | null,
  packId: string
): string {
  const manifestName = catalog?.[packId]?.manifest?.name?.trim()
  return manifestName || formatAvatarPackId(packId)
}

export function resolveAvatarPackId(
  catalog: AvatarPackCatalogIndex,
  requestedPack: string | undefined
): string | null {
  if (
    requestedPack &&
    catalog[requestedPack] &&
    getAvatarPackCharacters(catalog, requestedPack).length > 0
  ) {
    return requestedPack
  }
  return getAvatarPackIds(catalog)[0] ?? null
}

export function resolveAvatarPackCharacterIndex(
  catalog: AvatarPackCatalogIndex,
  pack: string,
  charIndex: number
): number {
  const key = resolveAvatarPackCharacterKey(catalog, pack, charIndex)
  if (key === null) {
    return 0
  }
  const parsed = Number.parseInt(key, 10)
  return Number.isNaN(parsed) ? 0 : parsed
}

export async function loadAvatarPackAnimation(
  pack: string,
  fileName: string
): Promise<AvatarKeyframedAnimation | null> {
  if (!/^[A-Za-z0-9_-]+$/.test(pack) || !/^[A-Za-z0-9_.-]+\.json$/.test(fileName)) {
    return null
  }
  const key = `${catalogVersion}:${pack}:${fileName}`
  const hit = animationCache.get(key)
  if (hit) {
    return hit
  }
  try {
    const url = avatarPackAssetUrl(`packs/${pack}/animations_json/${fileName}`)
    const resp = await fetch(url)
    if (!resp.ok) {
      return null
    }
    const raw: unknown = await resp.json()
    const animation = sanitizeAvatarPackAnimation(raw)
    if (!animation) {
      return null
    }
    animationCache.set(key, animation)
    if (animationCache.size > MAX_CACHED_ANIMATIONS) {
      const oldest = animationCache.keys().next()
      if (!oldest.done) {
        animationCache.delete(oldest.value)
      }
    }
    return animation
  } catch {
    return null
  }
}
