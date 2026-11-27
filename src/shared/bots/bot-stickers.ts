import {
  normalizeRuntimePathForComparison,
  resolveRuntimePath
} from '../file-access/cross-platform-path'

export const BOT_STICKERS_DIRECTORY = 'stickers'

const STANDARD_STICKER_PATH = new RegExp(`/\\.orca/bots/[^/]+/${BOT_STICKERS_DIRECTORY}/.+`)

export function isBotStickerPath(path: string, botHome?: string | null): boolean {
  const normalized = normalizeRuntimePathForComparison(path)
  if (STANDARD_STICKER_PATH.test(normalized)) {
    return true
  }
  if (!botHome) {
    return false
  }
  const directory = resolveRuntimePath(botHome, BOT_STICKERS_DIRECTORY)
  return normalized.startsWith(`${normalizeRuntimePathForComparison(directory)}/`)
}
