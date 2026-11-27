import { isOrcaSessionId, type OrcaSessionId } from '../agent-session/identity/orca-session-address'
import {
  canonicalExecutionHostId,
  isUnresolvedOwnerHostId,
  type ExecutionHostId
} from '../execution-host/execution-host'
import { parsePaneKey } from '../workspace-layout/stable-pane-id'

export type InboxSessionLink = {
  environmentId: string
  worktreeId: string
  paneKey: string
  sessionId: OrcaSessionId
  hostId: ExecutionHostId | null
}

const LINK_PREFIX = 'orca://inbox/session?'
const PARAMETERS = new Set(['environment', 'workspace', 'pane', 'id', 'host'])

function readValue(params: URLSearchParams, key: string, maxLength: number): string | null {
  const value = params.get(key)
  return value && value.length <= maxLength && value === value.trim() && !/\p{Cc}/u.test(value)
    ? value
    : null
}

export function parseInboxSessionLink(value: string): InboxSessionLink | null {
  if (!value.startsWith(LINK_PREFIX) || value.length > 8192 || value.includes('#')) {
    return null
  }
  const params = new URLSearchParams(value.slice(LINK_PREFIX.length))
  if ([...params.keys()].some((key) => !PARAMETERS.has(key) || params.getAll(key).length !== 1)) {
    return null
  }
  const environmentId = readValue(params, 'environment', 256)
  const worktreeId = readValue(params, 'workspace', 4096)
  const paneKey = readValue(params, 'pane', 512)
  const sessionId = readValue(params, 'id', 256)
  const hostId = canonicalExecutionHostId(readValue(params, 'host', 512))
  if (
    !environmentId ||
    !worktreeId ||
    !paneKey ||
    !parsePaneKey(paneKey) ||
    !sessionId ||
    !isOrcaSessionId(sessionId) ||
    (params.has('host') && (!hostId || isUnresolvedOwnerHostId(hostId)))
  ) {
    return null
  }
  return { environmentId, worktreeId, paneKey, sessionId, hostId }
}
