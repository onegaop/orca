import { callRuntimeRpc } from '@/runtime/rpc/calls/runtime-rpc-call'
import { captureRuntimeEnvironmentRequestRevision } from '@/runtime/rpc/environment-revisions/runtime-environment-revision'
import { bindTerminalKittyFileReader } from '@/lib/pane-manager/terminal-rendering/terminal-kitty-file-reader'
import { decodeBase64Bytes } from '@/lib/base64-bytes'
import {
  throwIfSignalAborted,
  waitForPromiseWithSignal
} from '../../../../../../shared/concurrency/abort-signal-reason'
import {
  HOST_TERMINAL_SURFACE_SEPARATOR,
  toHostSessionTabId
} from '../../../../../../shared/workspace-layout/terminal-surface-id'
import { toRemoteRuntimePtyId } from '../../../../../../shared/remote-runtime/remote-runtime-pty-id'
import type { RuntimeTerminalResolvePane } from '../../../../../../shared/terminal/runtime/runtime-terminal-contracts'
import type { RuntimeClientTarget } from '../../../../../../shared/remote-runtime/host-catalog/runtime-client-target'
import type { ConnectPanePtySession } from '../connect-pane-pty-session'

type CachedResolvedPane = {
  ptyId: string
  generation: number
  targetKey: string
  terminal: RuntimeTerminalResolvePane
}

export function installPtyKittyFileReader(session: ConnectPanePtySession): void {
  const lifetime = new AbortController()
  let cachedResolvedPane: CachedResolvedPane | null = null

  const unbind = bindTerminalKittyFileReader(session.pane.terminal, async (request) => {
    const ptyId = session.transport.getPtyId()
    if (!ptyId || session.disposed || session.terminalOwnerUnresolved) {
      throw new Error('Terminal file transport is unavailable')
    }
    const generation = session.transportStreamGeneration
    const environmentId = session.runtimeEnvironmentId
    const signal = AbortSignal.any([request.signal, lifetime.signal, AbortSignal.timeout(5000)])
    const target: RuntimeClientTarget =
      environmentId === null ? { kind: 'local' } : { kind: 'environment', environmentId }
    const targetKey = target.kind === 'local' ? 'local' : `env:${target.environmentId}`
    const options = {
      signal,
      timeoutMs: 5000,
      suppressFeatureInteraction: true,
      expectedEnvironmentPairingRevision:
        target.kind === 'environment'
          ? captureRuntimeEnvironmentRequestRevision(target.environmentId)
          : undefined
    }
    const isStillBound = (): boolean =>
      !session.disposed &&
      !session.terminalOwnerUnresolved &&
      session.transport.getPtyId() === ptyId &&
      session.transportStreamGeneration === generation &&
      session.runtimeEnvironmentId === environmentId

    const assertStillBound = (): void => {
      throwIfSignalAborted(signal)
      if (!isStillBound()) {
        throw new Error('Terminal binding changed')
      }
    }

    const resolvePaneTerminal = async (): Promise<RuntimeTerminalResolvePane> => {
      const resolved = await waitForPromiseWithSignal(
        callRuntimeRpc<{ terminal: RuntimeTerminalResolvePane }>(
          target,
          'terminal.resolvePane',
          {
            paneKey:
              target.kind === 'environment'
                ? `${toHostSessionTabId(session.deps.tabId).split(HOST_TERMINAL_SURFACE_SEPARATOR)[0]}:${session.pane.leafId}`
                : session.cacheKey,
            worktreeId: session.deps.worktreeId
          },
          options
        ),
        signal
      )
      const resolvedPtyId =
        target.kind === 'environment'
          ? toRemoteRuntimePtyId(resolved.terminal.handle, target.environmentId)
          : resolved.terminal.ptyId
      assertStillBound()
      if (!resolved.terminal.ptyId || resolvedPtyId !== ptyId) {
        throw new Error('Terminal binding changed')
      }
      cachedResolvedPane = {
        ptyId,
        generation,
        targetKey,
        terminal: resolved.terminal
      }
      return resolved.terminal
    }

    const readFromResolved = async (
      terminalInfo: RuntimeTerminalResolvePane
    ): Promise<{ base64: string }> => {
      assertStillBound()
      return waitForPromiseWithSignal(
        callRuntimeRpc<{ base64: string }>(
          target,
          'terminal.readKittyFile',
          {
            terminal: terminalInfo.handle,
            path: request.path,
            ...(terminalInfo.incarnationId
              ? { expectedIncarnationId: terminalInfo.incarnationId }
              : {}),
            offset: request.offset,
            ...(request.length !== undefined ? { length: request.length } : {})
          },
          options
        ),
        signal
      )
    }

    const cached = cachedResolvedPane
    const cacheHit =
      cached?.ptyId === ptyId && cached.generation === generation && cached.targetKey === targetKey
    let result: { base64: string }
    if (cacheHit) {
      try {
        result = await readFromResolved(cached.terminal)
      } catch (error) {
        if (signal.aborted || !isStillBound()) {
          throw error
        }
        if (cachedResolvedPane === cached) {
          cachedResolvedPane = null
        }
        const fresh = await resolvePaneTerminal()
        result = await readFromResolved(fresh)
      }
    } else {
      const fresh = await resolvePaneTerminal()
      result = await readFromResolved(fresh)
    }

    assertStillBound()
    if (typeof result.base64 !== 'string' || result.base64.length > 2_796_204) {
      throw new Error('Terminal image exceeds transport limit')
    }
    const bytes = decodeBase64Bytes(result.base64)
    if (bytes.length > 2 * 1024 * 1024) {
      throw new Error('Terminal image exceeds transport limit')
    }
    return bytes
  })
  session.cleanupKittyFileReader = () => {
    cachedResolvedPane = null
    lifetime.abort()
    unbind()
  }
}
