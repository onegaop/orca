import { useTranslate } from '@/i18n/use-translate'
import {
  useEffect,
  useLayoutEffect,
  type KeyboardEvent,
  type MouseEvent,
  type RefObject
} from 'react'
import { useLatestHandler } from '@/lib/use-latest-handler'
import { cn } from '@/lib/class-names'
import { WorkerDockGlyph } from './WorkerDockGlyph'
import type { WorkerDockGlyph as Glyph } from './worker-dock-card-order'

// Where Jump to latest rests while the open panel rises over the transcript: 8px above it.
const JUMP_LIFT = '--native-chat-worker-jump-lift'

// The chip's own row at the dock's top, so it never covers transcript text; the open panel rises
// from it over the transcript.
export const WORKER_DOCK_FLOAT_CLASS =
  'pointer-events-none relative z-20 flex h-[26px] shrink-0 flex-col [&:not(:last-child)]:mb-2 [[data-native-chat-dock-fit~=dock]_&]:h-auto'
// Raised over the transcript, opaque even when the chat's message-box surface is translucent.
export const WORKER_DOCK_SURFACE_CLASS =
  'pointer-events-auto border border-border bg-chat-canvas bg-[linear-gradient(var(--color-chat-composer-surface),var(--color-chat-composer-surface))] text-foreground [[data-native-chat-dock-fit~=dock]_&]:static'

/** The chip's one dot: the worst state among the workers. Red needs you, the dot grid while
 *  work runs, yellow waiting, green done; false (nothing could be read) is a grey ring. */
function WorkerDockChipDot({ glyph }: { glyph: Glyph | false }) {
  if (glyph === 'running') {
    return <WorkerDockGlyph glyph="running" chip />
  }
  return (
    <span aria-hidden="true" className="inline-flex size-3 shrink-0 items-center justify-center">
      <span
        className={cn(
          'block size-2 rounded-full',
          (glyph === 'ask' || glyph === 'failed') && 'bg-destructive',
          glyph === 'queued' && 'bg-status-warning',
          glyph === 'done' && 'bg-status-success',
          glyph === false && 'border-[1.5px] border-muted-foreground'
        )}
      />
    </span>
  )
}

/** The worker chip ("3 running"); while the list is open above it, the same chip, still one button
 *  with its text centered where it was, is the list's bottom row, so a press aimed at the chip as it
 *  opens under the pointer lands on it. */
export function WorkerDockPill({
  pill,
  glyph,
  label,
  spokenLabel = label,
  latest,
  total,
  commandsOnly = false,
  expanded,
  listId,
  onToggle,
  onKeyDown
}: {
  pill: RefObject<HTMLButtonElement | null>
  glyph: Glyph | false
  /** The chip's text: the one worker's title, how many run or need you, or what is known. */
  label: string
  /** The chip's count for assistive technology, both groups in full. */
  spokenLabel?: string
  /** Only background commands are listed: the running chip draws a terminal, not the worker grid. */
  commandsOnly?: boolean
  /** The most relevant worker's title, for assistive technology. */
  latest: string
  total: number
  expanded: boolean
  listId: string
  onToggle: (event: MouseEvent<HTMLButtonElement>) => void
  onKeyDown: (event: KeyboardEvent<HTMLButtonElement>) => void
}) {
  const t = useTranslate()
  return (
    <div
      className={cn(
        'flex h-6 shrink-0 items-center rounded-b-[inherit] border-t transition-colors duration-[280ms]',
        expanded ? 'border-border' : 'border-transparent'
      )}
    >
      <button
        ref={pill}
        type="button"
        data-worker-dock-pill=""
        aria-expanded={expanded}
        aria-controls={expanded ? listId : undefined}
        aria-label={
          total <= 1 && !commandsOnly
            ? undefined
            : t('components.native-chat.workerDock.chipLabel', '{{label}}, latest: {{title}}', {
                label: spokenLabel,
                title: latest
              })
        }
        className="flex h-full min-w-0 flex-1 items-center justify-center gap-1.5 rounded-[inherit] px-2.5 text-xs whitespace-nowrap hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        onClick={onToggle}
        onKeyDown={onKeyDown}
      >
        {commandsOnly && glyph === 'running' ? (
          <WorkerDockGlyph glyph={glyph} chip terminal />
        ) : (
          <WorkerDockChipDot glyph={glyph} />
        )}
        <span data-worker-dock-pill-title="" className="min-w-0 truncate">
          {label}
        </span>
      </button>
    </div>
  )
}

// A dialog, menu or toast a row opened is portalled out of the card but still belongs to it.
const KEEPS_CARD_OPEN =
  '[role="dialog"],[role="alertdialog"],[data-radix-popper-content-wrapper],[data-sonner-toaster]'

/** While the card is open, a press anywhere outside the pill and the card folds it, as Escape does. */
export function useWorkerDockOutsidePress(
  root: RefObject<HTMLElement | null>,
  open: boolean,
  onOutside: () => void
): void {
  const fold = useLatestHandler(onOutside)
  useEffect(() => {
    if (!open) {
      return
    }
    const press = (event: PointerEvent) => {
      const target = event.target
      if (!(target instanceof Element) || root.current?.contains(target)) {
        return
      }
      // Folding under a row's dialog would unmount the row it returns focus to. This pane's Jump to
      // latest shares the card's slot: folding on its press would move it before the click lands.
      // Another pane's Jump is just outside.
      const pane = root.current?.closest('[data-native-chat-root]')
      const ownJump = Boolean(
        pane?.contains(target) && target.closest('[data-native-chat-jump-latest]')
      )
      if (!ownJump && !target.closest(KEEPS_CARD_OPEN)) {
        fold()
      }
    }
    document.addEventListener('pointerdown', press, true)
    return () => document.removeEventListener('pointerdown', press, true)
  }, [root, open, fold])
}

/** While the panel is open, and until it has folded, Jump to latest rests 8px above where the
 *  panel ends up rather than hiding behind it. Read from the settled parts (borders, chip row and
 *  the list's own height), and again only when a height changes, so the morph's frames, which
 *  only change widths and the clipped track, cost nothing. */
export function useWorkerDockJumpLift(
  card: RefObject<HTMLElement | null>,
  content: RefObject<HTMLElement | null>,
  open: boolean
): void {
  useLayoutEffect(() => {
    const element = card.current
    const list = content.current
    const chip = element?.lastElementChild
    const pane = element?.closest<HTMLElement>('[data-native-chat-root]')
    const dock = element?.closest<HTMLElement>('[data-native-chat-dock]')
    if (
      !open ||
      !element ||
      !list ||
      !(chip instanceof HTMLElement) ||
      !pane ||
      !dock ||
      typeof ResizeObserver === 'undefined'
    ) {
      return
    }
    // The transcript, where Jump rests, ends at the dock's top; the panel rises past it.
    const lift = () => {
      const full =
        element.offsetHeight - element.clientHeight + chip.offsetHeight + list.offsetHeight
      const top = element.getBoundingClientRect().bottom - full
      pane.style.setProperty(JUMP_LIFT, `${dock.getBoundingClientRect().top - top + 8}px`)
    }
    const heights = new Map<Element, number>()
    const observer = new ResizeObserver((entries) => {
      let changed = false
      for (const entry of entries) {
        const height = entry.borderBoxSize[0]?.blockSize ?? entry.contentRect.height
        changed = changed || heights.get(entry.target) !== height
        heights.set(entry.target, height)
      }
      if (changed) {
        lift()
      }
    })
    observer.observe(list)
    observer.observe(dock)
    lift()
    return () => {
      observer.disconnect()
      pane.style.removeProperty(JUMP_LIFT)
    }
  }, [card, content, open])
}
