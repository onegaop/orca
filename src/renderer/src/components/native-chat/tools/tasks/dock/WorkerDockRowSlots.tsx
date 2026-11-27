import { useTranslate } from '@/i18n/use-translate'
import type { NativeChatToolRunDrawnRow } from '../../runs/use-native-chat-tool-run-window'
import { WorkerDockRow, type WorkerDockRowView } from './WorkerDockRow'
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { defaultRangeExtractor } from '@tanstack/react-virtual'

/** Keep a focused row mounted even if it scrolls out of the virtual window. */
export function useWorkerDockRangeWithFocus(
  items: readonly { id: string }[],
  focused: string | null
) {
  const activeIndex = useMemo(() => items.findIndex((row) => row.id === focused), [items, focused])
  return useCallback(
    (range: Parameters<typeof defaultRangeExtractor>[0]) => {
      const indices = defaultRangeExtractor(range)
      return activeIndex >= 0 && !indices.includes(activeIndex)
        ? [...indices, activeIndex].sort((a, b) => a - b)
        : indices
    },
    [activeIndex]
  )
}

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
  workerCount,
  grouped,
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
  workerCount: number
  grouped: boolean
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
  const t = useTranslate()
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
  const commandsLabel = t('components.native-chat.workerDock.commandsRegion', 'Background commands')
  const workersLabel = t('components.native-chat.workerDock.workersRegion', 'Workers')
  const renderRow = (item: NativeChatToolRunDrawnRow, drawnIndex: number) => {
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
          {grouped && item.index === workerCount ? (
            <div
              aria-hidden="true"
              data-worker-dock-group-label=""
              className="mt-1 flex h-6 items-center border-t border-border pl-2 pt-1 text-xs text-muted-foreground"
            >
              <span className="min-w-0 truncate">{commandsLabel}</span>
            </div>
          ) : null}
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
  }
  const workers = drawn.filter((item) => item.index < workerCount)
  const commands = drawn.filter((item) => item.index >= workerCount)
  return (
    <div style={{ height: small ? 'auto' : totalSize, position: 'relative' }}>
      <div
        role={grouped && workers.length ? 'group' : undefined}
        aria-label={grouped && workers.length ? workersLabel : undefined}
      >
        {workers.map(renderRow)}
      </div>
      <div
        role={grouped && commands.length ? 'group' : undefined}
        aria-label={grouped && commands.length ? commandsLabel : undefined}
      >
        {commands.map((item, index) => renderRow(item, workers.length + index))}
      </div>
    </div>
  )
}
