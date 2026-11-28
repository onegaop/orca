import type { AvatarAnimationState, AvatarPackCatalogIndex } from './avatar-pack-types'

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function isAvatarPackCatalogIndex(value: unknown): value is AvatarPackCatalogIndex {
  return (
    isRecord(value) &&
    Object.entries(value).every(
      ([pack, entry]) =>
        /^[A-Za-z0-9_-]+$/.test(pack) &&
        isRecord(entry) &&
        isRecord(entry.manifest) &&
        (entry.manifest.name === undefined || typeof entry.manifest.name === 'string') &&
        isRecord(entry.characters) &&
        Object.entries(entry.characters).every(
          ([key, states]) =>
            /^\d+$/.test(key) &&
            Number.isSafeInteger(Number(key)) &&
            isRecord(states) &&
            Object.values(states).every(
              (variants) =>
                Array.isArray(variants) &&
                variants.every(
                  (variant) =>
                    isRecord(variant) &&
                    typeof variant.file === 'string' &&
                    /^[A-Za-z0-9_.-]+\.json$/.test(variant.file)
                )
            )
        )
    )
  )
}

export function getAvatarPackCharacters(catalog: AvatarPackCatalogIndex, pack: string): string[] {
  const entry = catalog[pack]
  if (!entry?.characters) {
    return []
  }
  return Object.keys(entry.characters).sort((a, b) => {
    const na = Number(a)
    const nb = Number(b)
    if (!Number.isNaN(na) && !Number.isNaN(nb)) {
      return na - nb
    }
    return a.localeCompare(b)
  })
}

export function resolveAvatarPackCharacterKey(
  catalog: AvatarPackCatalogIndex,
  pack: string,
  charIndex: number
): string | null {
  const entry = catalog[pack]
  if (!entry?.characters) {
    return null
  }
  const exactKey = String(charIndex)
  if (charIndex >= 0 && Object.hasOwn(entry.characters, exactKey)) {
    return exactKey
  }
  const keys = getAvatarPackCharacters(catalog, pack)
  if (keys.length === 0) {
    return null
  }
  const safeIdx =
    ((Math.trunc(Number.isFinite(charIndex) ? charIndex : 0) % keys.length) + keys.length) %
    keys.length
  return keys[safeIdx] ?? keys[0] ?? null
}

export function resolveAvatarPackAnimationFile(
  catalog: AvatarPackCatalogIndex,
  pack: string,
  charIndex: number,
  state: AvatarAnimationState
): string | null {
  const entry = catalog[pack]
  if (!entry) {
    return null
  }
  const charKey = resolveAvatarPackCharacterKey(catalog, pack, charIndex)
  if (charKey === null) {
    return null
  }
  const charData = entry.characters[charKey]
  if (!charData) {
    return null
  }
  const variants = charData[state]
  if (variants && variants.length > 0) {
    return variants[0]?.file ?? null
  }
  const idleVariants = charData.idle
  if (idleVariants && idleVariants.length > 0) {
    return idleVariants[0]?.file ?? null
  }
  for (const list of Object.values(charData)) {
    if (list && list.length > 0 && list[0]?.file) {
      return list[0].file
    }
  }
  return null
}
