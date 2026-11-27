import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type PointerEvent,
  type RefObject
} from 'react'
import { useLatestHandler } from '@/lib/use-latest-handler'
import { workerDockRowTitle, type WorkerDockRowView } from './WorkerDockRow'
import { forceLayoutReflow } from '@/lib/overlay-interaction/force-layout-reflow'

const OPEN_DELAY = 120
const CLOSE_DELAY = 250
// Matches --worker-dock-morph-ms: rows stay drawn while the shape folds around them.
const FOLD_MS = 280
// The last row's rise ends here: 20% of the morph, ten 22ms steps, then the 280ms rise.
const ENTER_MS = FOLD_MS * 0.2 + 10 * 22 + FOLD_MS
// A row's dialog or menu is portalled out of the card, so leaving the card to use it must not fold it.
const KEEPS_OPEN = '[role="dialog"],[role="alertdialog"],[role="menu"]'

/** One chip-and-list shape: rows stay mounted until the fold finishes so they fade out as it
 *  shrinks, and the width runs between measured pixel ends: it grows from the chip's last drawn
 *  width (`fit-content` would resolve against the rows that mount with the open list) and folds
 *  to the folded chip's measured width. */
export function useWorkerDockMorph(
  card: RefObject<HTMLElement | null>,
  expanded: boolean,
  /** Everything the folded chip's text is made from (its counts, and a lone worker's title once its
   *  details arrive); when any of it changes, a running fold re-aims at the new width. */
  counts: readonly (string | number)[],
  workers: readonly { id: string }[],
  rows: ReadonlyMap<string, WorkerDockRowView>
): { mounted: boolean; entering: boolean } {
  const lone = workers.length === 1 ? rows.get(workers[0].id) : undefined
  const labelKey = [...counts, lone ? workerDockRowTitle(lone) : ''].join('|')
  const [phase, setPhase] = useState<'idle' | 'entering' | 'folding'>('idle')
  const [previous, setPrevious] = useState(expanded)
  const [reversed, setReversed] = useState(false)
  // The new phase counts in this render too: one pass with the rows unmounted would reset the
  // list's virtual window to its top before the fold draws.
  let current = phase
  if (previous !== expanded) {
    current = expanded ? 'entering' : 'folding'
    setPrevious(expanded)
    setPhase(current)
    // Reopened while it still folds: the running width transition turns back from where it is.
    setReversed(expanded && phase === 'folding')
  }
  useEffect(() => {
    if (phase === 'idle') {
      return
    }
    const timer = setTimeout(() => setPhase('idle'), phase === 'entering' ? ENTER_MS : FOLD_MS)
    return () => clearTimeout(timer)
  }, [phase])
  const mounted = expanded || current === 'folding'
  const width = useRef(0)
  useEffect(() => {
    const element = card.current
    // Only the settled folded width is a start point, so the shape's growth and fold are not observed.
    if (mounted || !element || typeof ResizeObserver === 'undefined') {
      return
    }
    const observer = new ResizeObserver(() => {
      width.current = element.offsetWidth
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [card, mounted])
  const folding = !expanded && mounted
  useLayoutEffect(() => {
    const element = card.current
    if (!folding || !element) {
      return
    }
    // Fold toward the folded chip's measured width, not `fit-content`: a label that changes as it
    // folds or reopens would move a keyword end point mid-flight. A new label re-aims it from
    // wherever it is.
    const from = element.getBoundingClientRect().width
    element.style.setProperty('transition', 'none')
    element.style.setProperty('width', 'fit-content')
    const to = element.offsetWidth
    jump(element, from)
    element.style.setProperty('width', `${to}px`)
  }, [card, folding, labelKey])
  useLayoutEffect(() => {
    const element = card.current
    if (folding || !element) {
      return
    }
    // Open, or folded at rest: the stylesheet's width again (a running fold retargets to 100%).
    if (expanded && !reversed && width.current) {
      jump(element, width.current)
    }
    element.style.removeProperty('width')
  }, [card, expanded, folding, reversed])
  return { mounted, entering: expanded && current === 'entering' }
}

/** Sets the card's width at once, as the start of the transition that follows. */
function jump(element: HTMLElement, width: number): void {
  element.style.setProperty('transition', 'none')
  element.style.setProperty('width', `${width}px`)
  forceLayoutReflow(element)
  element.style.removeProperty('transition')
}

/** A mouse resting on the chip opens it; leaving folds it again, unless a press pinned it open. */
export function useWorkerDockHover({
  root,
  expanded,
  onOpen,
  onClose,
  onEnter,
  onLeave
}: {
  root: RefObject<HTMLElement | null>
  expanded: boolean
  onOpen: () => void
  onClose: () => void
  /** Every pointer's entry and exit, touch included. */
  onEnter: () => void
  onLeave: () => void
}) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const byHover = useRef(false)
  const cancel = () => {
    if (timer.current) {
      clearTimeout(timer.current)
      timer.current = null
    }
  }
  const open = useLatestHandler(() => {
    timer.current = null
    byHover.current = true
    onOpen()
  })
  const close = useLatestHandler(() => {
    timer.current = null
    const element = root.current
    // A keyboard user inside the list, or a row's dialog, keeps it open.
    if (!element || element.querySelector(':focus-visible') || document.querySelector(KEEPS_OPEN)) {
      return
    }
    byHover.current = false
    onClose()
  })
  const escape = useLatestHandler(() => {
    cancel()
    byHover.current = false
    onClose()
  })
  useEffect(() => {
    if (!expanded) {
      byHover.current = false
      return
    }
    // Opened by the pointer while focus stays elsewhere: Escape folds it first, before the message
    // box takes Escape (to stop a turn), unless a dialog or menu is open to take it.
    const key = (event: KeyboardEvent) => {
      // Focus inside the dock: its own Escape folds it and brings focus back to the chip.
      if (
        event.key === 'Escape' &&
        byHover.current &&
        !root.current?.contains(document.activeElement) &&
        !document.querySelector(KEEPS_OPEN)
      ) {
        event.preventDefault()
        event.stopPropagation()
        escape()
      }
    }
    document.addEventListener('keydown', key, true)
    return () => document.removeEventListener('keydown', key, true)
  }, [expanded, escape, root])
  useEffect(() => cancel, [])
  const pointer = (event: PointerEvent) =>
    event.pointerType === 'mouse' || event.pointerType === 'pen'
  return {
    enter(event: PointerEvent) {
      onEnter()
      if (!pointer(event)) {
        return
      }
      cancel()
      if (!expanded) {
        timer.current = setTimeout(open, OPEN_DELAY)
      }
    },
    leave(event: PointerEvent) {
      onLeave()
      if (!pointer(event)) {
        return
      }
      cancel()
      if (expanded && byHover.current) {
        timer.current = setTimeout(close, CLOSE_DELAY)
      }
    },
    /** A mouse or pen press on a chip the pointer opened pins it open; returns whether it was used
     *  so. A key or touch press always toggles. */
    pin(press: { nativeEvent: Event }): boolean {
      cancel()
      const by = 'pointerType' in press.nativeEvent ? press.nativeEvent.pointerType : ''
      if ((by === 'mouse' || by === 'pen') && expanded && byHover.current) {
        byHover.current = false
        return true
      }
      return false
    }
  }
}
