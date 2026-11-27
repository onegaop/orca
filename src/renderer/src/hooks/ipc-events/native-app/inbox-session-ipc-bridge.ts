import { showAgentPaneUnavailable } from '@/components/terminal-pane/agent-status/stale-agent-row'
import { openExistingStructuredSession } from '@/lib/agent-session/open/open-existing-structured-session'
import { activateStructuredAgentSessionById } from '@/lib/agent-session/structured-agent-session-tab-activation'
import { revealTerminalPane } from '@/lib/workspace/activation/reveal-terminal-pane'
import { activateAndRevealWorkspace } from '@/lib/workspace/activation/worktree-activation'
import { callRuntimeRpc } from '@/runtime/rpc/calls/runtime-rpc-call'
import { runtimeTargetForOwnerEnvironment } from '@/runtime/rpc/targets/runtime-client-target'
import { useAppStore } from '@/store'
import type { AgentShowResult } from '../../../../../shared/agent-conversations/agent-conversation-contracts'
import {
  parseInboxSessionLink,
  type InboxSessionLink
} from '../../../../../shared/agent-conversations/inbox-session-link'
import { structuredAgentSessionIdFromTabId } from '../../../../../shared/agent-session/view/structured-agent-session-tab-id'
import {
  canonicalExecutionHostId,
  LOCAL_EXECUTION_HOST_ID,
  toRuntimeExecutionHostId
} from '../../../../../shared/execution-host/execution-host'
import { parsePaneKey } from '../../../../../shared/workspace-layout/stable-pane-id'

async function revealInboxSession(link: InboxSessionLink, signal: AbortSignal): Promise<boolean> {
  const pane = parsePaneKey(link.paneKey)
  const environmentId = link.environmentId === LOCAL_EXECUTION_HOST_ID ? null : link.environmentId
  if (!pane || signal.aborted) {
    return false
  }
  if (environmentId) {
    const environments = await window.api.runtimeEnvironments.list()
    if (!environments.some((environment) => environment.id === environmentId) || signal.aborted) {
      return false
    }
  }
  const target = runtimeTargetForOwnerEnvironment(environmentId)
  const result = await callRuntimeRpc<AgentShowResult>(
    target,
    'agent.show',
    { id: link.sessionId },
    {
      wake: false,
      signal,
      timeoutMs: 7_000
    }
  )
  const place = result.places.find(
    (row) =>
      row.orcaSessionId === link.sessionId &&
      row.worktreeId === link.worktreeId &&
      row.paneKey === link.paneKey &&
      (!link.hostId || canonicalExecutionHostId(row.hostId) === link.hostId)
  )
  if (!place || signal.aborted) {
    return false
  }
  const executionHostId = environmentId
    ? toRuntimeExecutionHostId(environmentId)
    : (canonicalExecutionHostId(place.hostId) ?? LOCAL_EXECUTION_HOST_ID)
  if (place.kind === 'terminal') {
    return revealTerminalPane({ worktreeId: place.worktreeId, executionHostId, ...pane })
  }
  const sessionId = structuredAgentSessionIdFromTabId(pane.tabId)
  if (!sessionId) {
    return false
  }
  const worktreeId = place.worktreeId
  const initialize = (): boolean =>
    !signal.aborted && Boolean(activateAndRevealWorkspace(worktreeId, { executionHostId }))
  if (initialize() && activateStructuredAgentSessionById({ worktreeId, sessionId, target })) {
    return true
  }
  const outcome = await openExistingStructuredSession(
    { workspaceId: worktreeId, sessionId },
    {
      target,
      signal,
      initialize,
      present: () => {}
    }
  )
  return outcome === 'activated' && !signal.aborted
}

export function registerInboxSessionIpcBridge(unsubs: (() => void)[]): void {
  let active: AbortController | undefined
  let disposed = false
  const pull = async (): Promise<void> => {
    if (disposed || !useAppStore.getState().workspaceSessionReady) {
      return
    }
    const url = await window.api.ui.consumePendingInboxSession()
    const link = url && parseInboxSessionLink(url)
    if (!link || disposed) {
      return
    }
    active?.abort()
    const request = new AbortController()
    active = request
    const opened = await revealInboxSession(link, request.signal).catch(() => false)
    if (!opened && !request.signal.aborted) {
      showAgentPaneUnavailable()
    }
  }
  const notify = (): void => {
    void pull().catch((error: unknown) => console.error('Failed to read the Inbox link:', error))
  }
  unsubs.push(window.api.ui.onInboxSessionPending(notify))
  unsubs.push(
    useAppStore.subscribe((state, previous) => {
      if (state.workspaceSessionReady && !previous.workspaceSessionReady) {
        notify()
      }
    })
  )
  unsubs.push(() => {
    disposed = true
    active?.abort()
  })
  notify()
}
