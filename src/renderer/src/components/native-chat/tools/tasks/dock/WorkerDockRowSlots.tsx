import type { NativeChatToolRunDrawnRow } from '../../runs/use-native-chat-tool-run-window'
import { WorkerDockRow, type WorkerDockRowView } from './WorkerDockRow'
import { useEffect, useState, type ReactNode } from 'react'

// Rows rise in 22ms apart once the open shape is ~20% grown; later rows share the last delay.
const rowDelay = (drawnIndex: number) =>
  `calc(var(--worker-dock-morph-ms) * 0.2 + ${Math.min(drawnIndex, 10) * 22}ms)`

// How long after the list starts opening a mounting row still counts as arriving with it: past the
// virtual window's first measure, before any scroll the user could make.
const ARRIVAL_MS = 80
// The open list shows at most six rows; the ones past them have nothing to show, so skip the work.
const RISING_ROWS = 8

/** A row's fade and rise wrapper. Whether it rises is decided once, as it mounts. */
function WorkerDockRise({
  rise,
  delay,
  children
}: {
  rise: boolean
  delay: string
  children: ReactNode
}) {
  const [rises] = useState(rise)
  return (
    <div
      data-worker-dock-morph-row=""
      data-worker-dock-rise={rises ? '' : undefined}
      style={{ animationDelay: delay }}
    >
      {children}
    </div>
  )
}

/** The open list's drawn rows: every row for a small roster, else the virtual window. */
export function WorkerDockRowSlots({
  drawn,
  ids,
  entering,
  small,
  totalSize,
  measureRow,
  rows,
  mixed,
  visible,
  pending,
  onOpen,
  onAction
}: {
  drawn: readonly NativeChatToolRunDrawnRow[]
  ids: readonly string[]
  /** The list is opening: the rows drawn with it rise in. */
  entering: boolean
  small: boolean
  totalSize: number
  measureRow: (node: HTMLDivElement | null) => void
  rows: ReadonlyMap<string, WorkerDockRowView>
  mixed: boolean
  visible: boolean
  pending: ReadonlySet<string>
  onOpen: (row: WorkerDockRowView, opener: HTMLElement) => void
  onAction: (row: WorkerDockRowView, action: 'stop' | 'clear') => void
}) {
  // Rows that mount in the opening's first moments rise in with it; rows a scroll mounts later
  // (even while it is still opening) show at once.
  const [late, setLate] = useState(false)
  if (!entering && late) {
    setLate(false)
  }
  useEffect(() => {
    if (!entering) {
      return
    }
    const timer = setTimeout(() => setLate(true), ARRIVAL_MS)
    return () => clearTimeout(timer)
  }, [entering])
  return (
    <div style={{ height: small ? 'auto' : totalSize, position: 'relative' }}>
      {drawn.map((item, drawnIndex) => {
        const id = ids[item.index]
        const row = rows.get(id)
        return (
          <div
            key={id}
            data-index={item.index}
            ref={small ? undefined : measureRow}
            style={{
              position: small ? 'relative' : 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              transform: small ? undefined : `translateY(${item.start}px)`
            }}
          >
            <WorkerDockRise
              rise={entering && !late && drawnIndex < RISING_ROWS}
              delay={rowDelay(drawnIndex)}
            >
              {/* One component either way, so focus on a loading row survives its details arriving. */}
              <WorkerDockRow
                id={id}
                row={row}
                mixed={mixed}
                visible={visible}
                pending={row ? pending.has(row.id) : false}
                onOpen={onOpen}
                onAction={onAction}
              />
            </WorkerDockRise>
          </div>
        )
      })}
    </div>
  )
}
