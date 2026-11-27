import { afterEach, describe, expect, it, vi } from 'vitest'
import type WebSocket from 'ws'
import { CdpWsProxy } from '../transport/cdp-ws-proxy'
import {
  connect,
  createMockWebContents,
  getSendCommandCalls,
  mockAsWebContents,
  nextMessage,
  sendAndReceive
} from '../transport/cdp-ws-proxy-test-harness'

vi.mock('electron', () => ({
  webContents: { fromId: vi.fn() }
}))

const MOVE = {
  id: 1,
  method: 'Input.dispatchMouseEvent',
  params: { type: 'mouseMoved', x: 5, y: 5 }
}
const PRESS = {
  id: 2,
  method: 'Input.dispatchMouseEvent',
  params: { type: 'mousePressed', x: 5, y: 5, button: 'left', clickCount: 1 }
}

let proxy: CdpWsProxy | null = null
let ws: WebSocket | null = null

afterEach(async () => {
  ws?.close()
  await proxy?.stop()
  proxy = null
  ws = null
})

// A throttled guest paints about once a second, and Chromium acks a mouse move only on the next frame.
async function throttledGuest(skipsInputWaits: boolean) {
  const mock = createMockWebContents()
  const moveAck = Promise.withResolvers<Record<string, unknown>>()
  mock.webContents.getType.mockReturnValue('webview')
  Object.assign(mock.webContents, { isOffscreen: () => false })
  mock.webContents.debugger.sendCommand.mockImplementation(async (method, params) =>
    method === 'Input.dispatchMouseEvent' && params?.type === 'mouseMoved' ? moveAck.promise : {}
  )
  proxy = new CdpWsProxy(mockAsWebContents(mock), () => () => {}, undefined, {
    show: async () => {},
    skipsInputWaits: () => skipsInputWaits
  })
  ws = await connect(await proxy.start())
  return { mock, ws, acknowledgeMove: moveAck.resolve }
}

describe('CdpPageInputCommands under --no-effects', () => {
  it('answers a move without its frame ack and still delivers the press after it', async () => {
    const { mock, ws } = await throttledGuest(true)

    expect(await sendAndReceive(ws, MOVE)).toMatchObject({ id: 1, result: {} })
    expect(await sendAndReceive(ws, PRESS)).toMatchObject({ id: 2, result: {} })
    const mouse = getSendCommandCalls(mock).filter(
      ([method]) => method === 'Input.dispatchMouseEvent'
    )
    expect(mouse.map(([, params]) => params?.type)).toEqual(['mouseMoved', 'mousePressed'])
  })

  it('waits for the move ack without --no-effects', async () => {
    const { mock, ws, acknowledgeMove } = await throttledGuest(false)
    const replies: unknown[] = []
    const reply = nextMessage(ws).then((value) => {
      replies.push(value)
      return value
    })
    ws.send(JSON.stringify(MOVE))
    await vi.waitFor(() =>
      expect(getSendCommandCalls(mock)).toContainEqual(
        expect.arrayContaining([MOVE.method, expect.objectContaining({ type: 'mouseMoved' })])
      )
    )
    expect(replies).toEqual([])
    acknowledgeMove({})
    await expect(reply).resolves.toMatchObject({ id: MOVE.id, result: {} })
  })
})
