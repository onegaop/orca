export const AVATAR_PACK_SCHEME = 'orca-avatar-pack'
export const AVATAR_PACK_CUSTOM_SCHEME = {
  scheme: AVATAR_PACK_SCHEME,
  privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true }
}

export const AVATAR_PACK_ASSET_PREFIX = `${AVATAR_PACK_SCHEME}://asset/`

export function avatarPackAssetUrl(relativePath: string): string {
  const clean = relativePath.replace(/^\/+/, '')
  return `${AVATAR_PACK_ASSET_PREFIX}${clean}`
}

export function avatarPackAssetRelativePath(url: string): string | null {
  const withoutQuery = url.split(/[?#]/, 1)[0] ?? ''
  if (withoutQuery.startsWith(AVATAR_PACK_ASSET_PREFIX)) {
    const rest = withoutQuery.slice(AVATAR_PACK_ASSET_PREFIX.length)
    return rest || null
  }
  return null
}
