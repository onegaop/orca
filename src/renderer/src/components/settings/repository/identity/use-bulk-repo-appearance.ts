import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { useAppStore } from '@/store'
import { useTranslate } from '@/i18n/use-translate'
import type { Repo } from '../../../../../../shared/repository/repo-types'
import { planBulkRepoAppearanceUpdates } from '../../../../../../shared/repository/appearance/bulk-repo-appearance'

export function useBulkRepoAppearance(repo: Repo): {
  canApplyToAll: boolean
  applyToAll: () => void
} {
  const t = useTranslate()
  const repos = useAppStore((state) => state.repos)
  const storeUpdateRepo = useAppStore((state) => state.updateRepo)
  const plan = useMemo(() => planBulkRepoAppearanceUpdates(repo, repos), [repo, repos])
  const [applying, setApplying] = useState(false)

  const applyToAll = async (): Promise<void> => {
    setApplying(true)
    const results = await Promise.allSettled(
      plan.map((entry) => storeUpdateRepo(entry.repoId, entry.updates, { hostId: entry.hostId }))
    ).finally(() => setApplying(false))
    const applied = plan.filter((_, index) => {
      const result = results[index]
      return result.status === 'fulfilled' && result.value
    })
    if (applied.length < plan.length) {
      toast.error(
        t(
          'auto.components.repo.ProjectPeek.applyToAllFailed',
          'Could not update some project badges.'
        )
      )
    }
    if (applied.length === 0) {
      return
    }
    toast(
      t('auto.components.repo.ProjectPeek.appliedToAll', 'Applied to {{count}} projects', {
        count: applied.length,
        defaultValue_one: 'Applied to {{count}} project'
      }),
      {
        action: {
          label: t('auto.components.repo.ProjectPeek.undo', 'Undo'),
          onClick: () => {
            for (const entry of applied) {
              void storeUpdateRepo(entry.repoId, entry.previous, { hostId: entry.hostId })
            }
          }
        }
      }
    )
  }

  return { canApplyToAll: !applying && plan.length > 0, applyToAll }
}
