import { avatarPackAssetUrl } from '../../shared/avatar-pack-scheme'
import type { ParsedBotAvatar } from '../../shared/bot-avatar'
import {
  isAvatarPackCatalogIndex,
  resolveAvatarPackAnimationFile
} from '../../shared/bots/avatar-packs/avatar-pack-catalog-selection'
import { sanitizeAvatarPackAnimation } from '../../shared/bots/avatar-packs/avatar-pack-svg'
import type {
  AvatarAnimationState,
  AvatarPackAnimationResponse
} from '../../shared/bots/avatar-packs/avatar-pack-types'
import { detectImageFileSignature } from '../../shared/file-content/image-file-signature'
import { readRasterImageDimensions } from '../../shared/file-preview/raster-image-dimensions'
import {
  handleAvatarPackAssetRequest,
  type AvatarPacksResolveOptions
} from './avatar-pack-protocol'

const MAX_ANIMATION_BYTES = 1.5 * 1024 * 1024
const MAX_TEXTURE_COUNT = 64
const MAX_TEXTURE_PIXELS = 16 * 1024 * 1024

async function readAsset(
  path: string,
  options: AvatarPacksResolveOptions,
  limit: number
): Promise<{ data: Buffer; mimeType: string | null } | null> {
  const response = await handleAvatarPackAssetRequest(
    { method: 'GET', url: avatarPackAssetUrl(path) },
    options,
    limit
  )
  return response.ok
    ? {
        data: Buffer.from(await response.arrayBuffer()),
        mimeType: response.headers.get('Content-Type')
      }
    : null
}

function parseJson(asset: Awaited<ReturnType<typeof readAsset>>): unknown {
  if (asset?.mimeType !== 'application/json') {
    return null
  }
  try {
    return JSON.parse(asset.data.toString('utf8'))
  } catch {
    return null
  }
}

export async function loadMobileAvatarPackAnimation(
  { pack, charIndex }: Extract<ParsedBotAvatar, { kind: 'avatar-pack' }>,
  state: AvatarAnimationState,
  options: AvatarPacksResolveOptions
): Promise<AvatarPackAnimationResponse | null> {
  const catalog = parseJson(await readAsset('catalog_index.json', options, MAX_ANIMATION_BYTES))
  if (!isAvatarPackCatalogIndex(catalog) || !Object.hasOwn(catalog, pack)) {
    return null
  }
  const file = resolveAvatarPackAnimationFile(catalog, pack, charIndex, state)
  if (!file) {
    return null
  }
  const animationAsset = await readAsset(
    `packs/${pack}/animations_json/${file}`,
    options,
    MAX_ANIMATION_BYTES
  )
  const animation = sanitizeAvatarPackAnimation(parseJson(animationAsset))
  if (!animationAsset || !animation) {
    return null
  }

  const paths = new Set<string>()
  for (const { tag, attrs } of animation.nodes) {
    if (tag === 'image' && attrs) {
      for (const path of [attrs.href, attrs['xlink:href']]) {
        if (path) {
          paths.add(path)
        }
      }
    }
  }
  let bytesLeft =
    MAX_ANIMATION_BYTES -
    Math.max(animationAsset.data.byteLength, Buffer.byteLength(JSON.stringify(animation)))
  if (bytesLeft < 0 || paths.size > MAX_TEXTURE_COUNT) {
    return null
  }
  let pixelsLeft = MAX_TEXTURE_PIXELS
  const textures: Record<string, string> = {}
  for (const path of paths) {
    const texture = await readAsset(`packs/${pack}/textures/${path}`, options, bytesLeft)
    if (
      !texture ||
      (texture.mimeType !== 'image/png' && texture.mimeType !== 'image/webp') ||
      detectImageFileSignature(texture.data)?.mimeType !== texture.mimeType
    ) {
      return null
    }
    const dimensions = readRasterImageDimensions(texture.data)
    if (!dimensions || dimensions.width * dimensions.height > pixelsLeft) {
      return null
    }
    pixelsLeft -= dimensions.width * dimensions.height
    bytesLeft -= texture.data.byteLength
    textures[path] = `data:${texture.mimeType};base64,${texture.data.toString('base64')}`
  }
  return { animation, textures }
}
