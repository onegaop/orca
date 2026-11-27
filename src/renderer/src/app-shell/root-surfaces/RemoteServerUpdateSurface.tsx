import { Suspense } from 'react'
import { lazyWithRetry as lazy } from '@/app-shell/startup/lazy-with-retry'
import { useAppStore } from '@/store'
import { OverlayBoundary } from './app-root-surface-boundaries'

const RemoteServerUpdateDialog = lazy(
  () => import('../../components/settings/runtime-environments/updates/RemoteServerUpdateDialog')
)

export function RemoteServerUpdateSurface(): React.JSX.Element | null {
  const open = useAppStore((state) => state.remoteServerUpdateDialogOpen)
  return open ? (
    <Suspense fallback={null}>
      <OverlayBoundary boundaryId="overlay.remote-server-update-dialog">
        <RemoteServerUpdateDialog />
      </OverlayBoundary>
    </Suspense>
  ) : null
}
