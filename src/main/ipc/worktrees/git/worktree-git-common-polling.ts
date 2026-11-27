import { createOnDemandScanGate } from './worktree-git-common-on-demand-scan-gate'
import { snapshotGitCommon } from './worktree-git-common-snapshot'
import { diffGitCommon } from './worktree-git-common-snapshot-diff'
import type {
  WorktreeBasePollEvent,
  WorktreeBaseSubscription,
  WorktreePollerWindowVisibility
} from '../creation/worktree-base-directory-poller'

// Fallback reads settled entries only on the backstop, including same-granule index writes.
const INDEX_BACKSTOP_TICKS = 15

export type GitCommonPollingSubscription = WorktreeBaseSubscription & {
  /** Run a gated check now without moving the timed sweep; false when skipped (busy, hidden or scanned recently). */
  poke: () => boolean
}

export type GitCommonPollingOptions = {
  /** Reconciliation directly probes in-place leaves each tick and forces a full sweep every N ticks. */
  reconciliationFullScanEveryTicks?: number
  /** Missing snapshots can outlive the native owner they originally retired. */
  onRootMissing?: (initial: boolean) => void
  /** Pokes skip when any scan started this recently; a reveal forces a sweep when the hide spanned an old tick this far apart. */
  minOnDemandScanIntervalMs?: number
}

// Require misses on separate ticks before distrusting the directory gate for the whole catalog.
const DIR_GATE_MISS_TICKS_TO_DISTRUST = 2

export async function startGitCommonPolling(
  commonDirPath: string,
  onEvents: (events: WorktreeBasePollEvent[]) => void,
  pollIntervalMs: number,
  visibility: WorktreePollerWindowVisibility,
  onFullScan?: () => void,
  includePrimary = true,
  getStatusRefPaths: () => readonly string[] = () => [],
  options: GitCommonPollingOptions = {}
): Promise<GitCommonPollingSubscription> {
  let disposed = false
  let ticking = false
  let tickCount = 0
  const reconciliationFullScanEveryTicks = options.reconciliationFullScanEveryTicks
  const isReconciliation = reconciliationFullScanEveryTicks !== undefined
  const fallbackRegistration = isReconciliation
    ? undefined
    : { quietTicksByPath: new Map<string, number>(), maxQuietTicks: INDEX_BACKSTOP_TICKS }
  // Filesystems can ignore child renames in directory metadata; detected misses force ungated sweeps.
  let entryDirGateTrusted = true
  let dirGateMissTicks = 0
  const onDemand = createOnDemandScanGate(options.minOnDemandScanIntervalMs, visibility)
  let pokeAfterScan = false
  let timerDueAt = 0
  let snapshot = await snapshotGitCommon(commonDirPath, {
    includePrimary,
    statusRefPaths: new Set(getStatusRefPaths()),
    onRootMissing: () => options.onRootMissing?.(true)
  })
  let timer: ReturnType<typeof setTimeout> | null = null
  let parkedWhileHidden = false

  // A poke leaves the timed chain alone; a timed tick that lands mid-poke runs once the poke ends.
  let deferredTimedTick: { forceFullScan: boolean } | null = null
  const tick = async (forceFullScan = false, poked = false): Promise<void> => {
    if (!poked) {
      if (timer) {
        clearTimeout(timer)
      }
      timer = null
    }
    if (disposed) {
      return
    }
    if (!visibility.isWindowVisible()) {
      if (!poked) {
        parkedWhileHidden = true
      }
      return
    }
    if (ticking) {
      if (!poked) {
        deferredTimedTick = { forceFullScan: forceFullScan || !!deferredTimedTick?.forceFullScan }
      }
      return
    }
    ticking = true
    onDemand.scanStarted(!poked)
    // Measure start-to-start cadence so scan duration does not add a full interval of lag.
    const startedAt = Date.now()
    if (!poked) {
      tickCount++
    }
    const shouldForceFullScan =
      (isReconciliation && !entryDirGateTrusted) ||
      forceFullScan ||
      (!poked && tickCount % (reconciliationFullScanEveryTicks ?? INDEX_BACKSTOP_TICKS) === 0)
    let dirGateMissed = false
    try {
      const next = await snapshotGitCommon(commonDirPath, {
        previous: snapshot,
        includePrimary,
        forceFullScan: shouldForceFullScan,
        statusRefPaths: new Set(getStatusRefPaths()),
        statInPlaceLeaves: isReconciliation,
        onDirGateMiss: isReconciliation
          ? () => {
              dirGateMissed = true
            }
          : undefined,
        // A present-to-missing edge already retires through the normal diff.
        onRootMissing:
          snapshot.worktreesDirSignature === 'missing'
            ? () => options.onRootMissing?.(false)
            : undefined,
        fallbackRegistration
      })
      if (disposed) {
        return
      }
      if (dirGateMissed && ++dirGateMissTicks >= DIR_GATE_MISS_TICKS_TO_DISTRUST) {
        entryDirGateTrusted = false
      }
      if (next.didFullScan) {
        onFullScan?.()
      }
      const events = diffGitCommon(commonDirPath, snapshot, next)
      snapshot = next
      if (events.length > 0) {
        onEvents(events)
      }
    } catch {
      // Transient fs error: keep the previous snapshot and retry next tick.
    } finally {
      ticking = false
    }
    if (pokeAfterScan && !disposed) {
      pokeAfterScan = false
      onDemand.retryWhenOpen(poke)
    }
    if (disposed) {
      return
    }
    const deferred = deferredTimedTick
    deferredTimedTick = null
    if (poked) {
      if (!deferred || timer) {
        return
      }
      // A gated timed tick that landed mid-poke is covered by it; forced and full-sweep ticks still run.
      const fullSweepDue =
        deferred.forceFullScan ||
        (isReconciliation && !entryDirGateTrusted) ||
        (tickCount + 1) % (reconciliationFullScanEveryTicks ?? INDEX_BACKSTOP_TICKS) === 0
      if (fullSweepDue) {
        void tick(deferred.forceFullScan)
        return
      }
      tickCount++
    } else if (deferred?.forceFullScan) {
      void tick(true)
      return
    }
    // Clamp wall-clock jumps so NTP cannot postpone refreshes beyond one interval.
    const nextDelay = Math.max(
      0,
      Math.min(pollIntervalMs, pollIntervalMs - (Date.now() - startedAt))
    )
    timerDueAt = performance.now() + nextDelay
    timer = setTimeout(() => void tick(), nextDelay)
    timer.unref?.()
  }

  const unsubscribeVisibility = visibility.onWindowBecameVisible(() => {
    const spannedOldTick = onDemand.hideSpannedOldTick()
    onDemand.clearHide()
    if (disposed || (!parkedWhileHidden && !spannedOldTick)) {
      return
    }
    parkedWhileHidden = false
    // Resume must force index reads because hidden writes can leave directory signatures unchanged.
    void tick(true)
  })

  timerDueAt = performance.now() + pollIntervalMs
  timer = setTimeout(() => void tick(), pollIntervalMs)
  timer.unref?.()

  function poke(): boolean {
    // A pending reveal sweep supersedes the gated check (focus can arrive before show/restore).
    const revealPending = parkedWhileHidden || onDemand.hideSpannedOldTick()
    if (disposed || revealPending || !visibility.isWindowVisible()) {
      return false
    }
    onDemand.noteRequest()
    // A running scan (possibly stalled on a hung mount) re-arms the retry only when it ends.
    if (ticking) {
      pokeAfterScan = true
      return false
    }
    if (onDemand.scannedRecently()) {
      onDemand.retryWhenOpen(poke)
      return false
    }
    // A full sweep due within 30 s of the first unserved activity covers it; a check now would only precede it.
    const fullSweepDueSoon =
      timer !== null &&
      onDemand.coversRequest(timerDueAt) &&
      ((isReconciliation && !entryDirGateTrusted) ||
        (tickCount + 1) % (reconciliationFullScanEveryTicks ?? INDEX_BACKSTOP_TICKS) === 0)
    if (fullSweepDueSoon) {
      return false
    }
    void tick(false, true)
    return true
  }

  return {
    poke,
    unsubscribe: async () => {
      disposed = true
      if (timer) {
        clearTimeout(timer)
      }
      unsubscribeVisibility()
      onDemand.dispose()
    }
  }
}
