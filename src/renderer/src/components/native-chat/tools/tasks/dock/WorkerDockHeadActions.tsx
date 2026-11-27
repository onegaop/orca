import { useTranslate } from '@/i18n/use-translate'
import { Button } from '@/components/ui/button'

/** Stop all, for a provider that can only stop everything at once: above the open list. */
function WorkerDockStopAll({ stopAll }: { stopAll?: { pending: boolean; onStop: () => void } }) {
  const t = useTranslate()
  return stopAll ? (
    <Button
      variant="ghost"
      size="xs"
      aria-disabled={stopAll.pending}
      onClick={() => {
        if (!stopAll.pending) {
          stopAll.onStop()
        }
      }}
    >
      {stopAll.pending
        ? t('components.native-chat.workerDock.stopping', 'Stopping…')
        : t('components.native-chat.workerDock.stopAll', 'Stop all')}
    </Button>
  ) : null
}

/** Clear failed, drawn only when two or more failures can be acknowledged. */
function WorkerDockClearFailed({
  clearable,
  clearing,
  onClearAll
}: {
  clearable: number
  clearing: boolean
  onClearAll: () => void
}) {
  const t = useTranslate()
  if (clearable < 2) {
    return null
  }
  return (
    <Button
      variant="ghost"
      size="xs"
      aria-label={t(
        'components.native-chat.workerDock.clearAllLabel',
        'Clear all {{count}} failed workers',
        { count: clearable, defaultValue_one: 'Clear failed worker' }
      )}
      aria-disabled={clearing}
      onClick={() => {
        if (!clearing) {
          onClearAll()
        }
      }}
    >
      {t('components.native-chat.workerDock.clearFailed', 'Clear failed')}
    </Button>
  )
}

/** The open list's bulk actions, in a slim row above the rows: Clear failed, then Stop all, each
 *  only when it applies, and no row at all when neither does. Kept off the chip's row, so a press
 *  aimed at a chip that opened under the pointer never lands on a bulk action. */
export function WorkerDockHeadActions({
  stopAll,
  ...clear
}: {
  clearable: number
  clearing: boolean
  onClearAll: () => void
  stopAll?: { pending: boolean; onStop: () => void }
}) {
  if (clear.clearable < 2 && !stopAll) {
    return null
  }
  return (
    <div data-worker-dock-actions="" className="flex items-center justify-end gap-1 pb-1">
      <WorkerDockClearFailed {...clear} />
      <WorkerDockStopAll stopAll={stopAll} />
    </div>
  )
}
