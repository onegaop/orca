import { Terminal } from '@xterm/xterm'
import { expect, it, vi } from 'vitest'
import { readTerminalKittyFile } from '@/lib/pane-manager/terminal-rendering/terminal-kitty-file-reader'
import type { ConnectPanePtySession } from '../connect-pane-pty-session'
import { installPtyKittyFileReader } from './pty-kitty-file-reader'

const { callRuntimeRpc } = vi.hoisted(() => ({ callRuntimeRpc: vi.fn() }))
vi.mock('@/runtime/rpc/calls/runtime-rpc-call', () => ({ callRuntimeRpc }))

it('rejects a cached file read from a superseded stream generation with the same PTY ID', async () => {
  const terminal = new Terminal()
  const session = {
    pane: { terminal },
    deps: { worktreeId: 'worktree' },
    cacheKey: 'pane',
    transport: { getPtyId: () => 'pty' },
    runtimeEnvironmentId: null,
    transportStreamGeneration: 1
  } as unknown as ConnectPanePtySession
  const oldRead = Promise.withResolvers<{ base64: string }>()
  callRuntimeRpc.mockImplementation(async (_target, method, params) => {
    if (method === 'terminal.resolvePane') {
      return { terminal: { ptyId: 'pty', handle: `stream-${session.transportStreamGeneration}` } }
    }
    if (params.path === '/old-read') {
      return oldRead.promise
    }
    return { base64: params.terminal === 'stream-1' ? 'AQ==' : 'Ag==' }
  })

  const read = (path: string): Promise<Uint8Array> =>
    readTerminalKittyFile(terminal, { path, offset: 0, signal: new AbortController().signal })

  installPtyKittyFileReader(session)
  try {
    expect(await read('/warm')).toEqual(Uint8Array.of(1))
    const staleRead = expect(read('/old-read')).rejects.toThrow('Terminal binding changed')
    session.transportStreamGeneration += 1
    expect(await read('/new-read')).toEqual(Uint8Array.of(2))
    oldRead.resolve({ base64: 'AQ==' })
    await staleRead
  } finally {
    session.cleanupKittyFileReader()
    terminal.dispose()
  }
})
