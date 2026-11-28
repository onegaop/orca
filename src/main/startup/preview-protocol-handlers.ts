import { protocol } from 'electron'
import { AVATAR_PACK_SCHEME } from '../../shared/avatar-pack-scheme'
import type { AvatarPacksResolveOptions } from '../avatar-packs/avatar-pack-protocol'
import { CONNECTOR_AVATAR_SCHEME } from '../../shared/connector-avatar-scheme'
import { MEDIA_PREVIEW_SCHEME } from '../../shared/file-preview/media-preview-scheme'
import { JIRA_IMAGE_SCHEME } from '../../shared/jira/jira-attachment-image'
import { installDocPreviewProtocolHandler } from '../browser/document-preview/doc-preview-protocol'

/** The protocol-scoped preview handlers, which must exist before any webview attaches. */
export function installPreviewProtocolHandlers(
  options?: Pick<AvatarPacksResolveOptions, 'getSettings'>
): void {
  protocol.handle(MEDIA_PREVIEW_SCHEME, async (request) => {
    const { handleMediaPreviewRequest } = await import('../media/media-preview-protocol')
    return handleMediaPreviewRequest(request)
  })
  protocol.handle(JIRA_IMAGE_SCHEME, async (request) => {
    const { handleJiraImageRequest } = await import('../jira/attachments/image-protocol')
    return handleJiraImageRequest(request)
  })
  protocol.handle(CONNECTOR_AVATAR_SCHEME, async (request) => {
    const { handleConnectorAvatarRequest } =
      await import('../connector-avatars/connector-avatar-protocol')
    return handleConnectorAvatarRequest(request)
  })
  installDocPreviewProtocolHandler()
  protocol.handle(AVATAR_PACK_SCHEME, async (request) => {
    const { handleAvatarPackAssetRequest } = await import('../avatar-packs/avatar-pack-protocol')
    return handleAvatarPackAssetRequest(request, options)
  })
}
