import React from 'react'
import type { VirtualItem } from '@tanstack/react-virtual'
import { cn } from '@/lib/class-names'
import type {
  WorkspaceStatus,
  WorkspaceStatusDefinition
} from '../../../../../../shared/worktree/types'
import '../../workspace-status/presentation/workspace-status'
import { getWorkspaceStatus } from '../../../../../../shared/workspace/status/workspace-statuses'
import { isActiveSidebarWorkspace } from '../../../../../../shared/sidebar-list/selection/active-workspace'
import type { WorktreeGroupBy } from '../../../../../../shared/sidebar-list/row-types'
import { getWorktreeHostIdentity } from '../../../../../../shared/worktree/host-qualified-identity'
import {
  getVirtualRowTransform,
  getWorktreeVirtualRowTransform,
  shouldUseHeaderTopSpacing
} from '../viewport/virtual-rows'
import type { LineageRowProjection } from '../listing/lineage-row-projection'
import { getRenderRowKey, type RenderRow } from '../listing/render-row'
import type { ImportedWorktreeCardActionState } from '../listing/imported-worktrees-card-actions'
import type { NewExternalWorktreesInboxActionState } from '../listing/new-external-worktrees-inbox-actions'
import type { useHostHeaderDrag } from '../drag/host-header-drag'
import { HostSectionHeader } from './HostSectionHeader'
import { renderFolderWorkspaceOption, type FolderWorkspaceRowContext } from './folder-row'
import type { LineageToggleHandler } from '../../workspace-card/identity/worktree-lineage-toggle-handler-cache'
import {
  renderImportedWorktreesVirtualRow,
  renderNewExternalWorktreesInboxVirtualRow,
  renderPendingCreationVirtualRow,
  renderProjectChatsVirtualRow
} from './notice-rows'
import { renderWorktreeItemRow, type WorktreeItemRowContext } from './item-row'
import { LineageGuides } from './lineage-guides'
import { renderWorktreeSectionHeaderRow } from './SectionHeader'
import type { SectionHeaderRowContext } from './section-header-row-context'
import type { WorktreeRowDragState } from '../drag/row-state'
import type { Translate } from '@/i18n/use-translate'
import { getFolderWorkspaceHostIdentity } from '../../../../../../shared/folder-workspaces/folder-workspace-worktree'
import { SidebarNumberHintBadge } from '../../number-shortcuts/SidebarNumberHintBadge'
import { workspaceRowNumberHintKey } from '../../number-shortcuts/sidebar-number-shortcut-targets'
import { getTreeRowLane, ProjectFrameEdge, type ProjectFramePiece } from './project-frame'
import { WORKTREE_CARD_SURFACE_MARGIN } from './indentation'

// Root rows arrive with their glyph 14px into the surface; the tree lane puts it 10px in.
const TREE_CONTENT_PULLBACK = 4

export type WorktreeVirtualRowContext = {
  dragUnitsByRow: ReadonlyMap<number, { identity: string }>
  hiddenDragRanges: readonly { start: number; end: number }[]
  projection: LineageRowProjection
  activeFamilyRoots: ReadonlySet<number>
  renderRows: RenderRow[]
  /** Project tree only: each row's piece of its open project's frame. */
  projectFrames?: ReadonlyMap<number, ProjectFramePiece>
  firstHeaderIndex: number
  activeStickyHeaderIndexRef: React.MutableRefObject<number | null>
  activeStickyHostIndexRef: React.MutableRefObject<number | null>
  measureVirtualRowElement: (element: HTMLDivElement | null) => void
  groupBy: WorktreeGroupBy
  workspaceStatuses: readonly WorkspaceStatusDefinition[]
  activeWorktreeId: string | null
  worktreeDragState: WorktreeRowDragState
  orderedHostIds: readonly string[]
  hostDrag: ReturnType<typeof useHostHeaderDrag>
  toggleGroupWithScrollAnchor: (groupKey: string) => void
  header: SectionHeaderRowContext
  item: WorktreeItemRowContext
  folderWorkspace: FolderWorkspaceRowContext
  importedWorktreeCardActionState: ReadonlyMap<string, ImportedWorktreeCardActionState>
  newExternalWorktreeInboxActionState: ReadonlyMap<string, NewExternalWorktreesInboxActionState>
  onShowImportedWorktrees: (projectId: string) => void
  onKeepImportedWorktreesHidden: (projectId: string) => void
  onOpenWorktreeVisibility: (
    repo: Parameters<SectionHeaderRowContext['projectActions']['onOpenWorktreeVisibility']>[0]
  ) => void
  onOpenSuppressExternalWorktreeInbox: (projectId: string) => void
  onWorkspaceStatusDragOver: (event: React.DragEvent, status: WorkspaceStatus) => void
  onWorkspaceStatusDragLeave: (event: React.DragEvent) => void
  onWorkspaceStatusDrop: (event: React.DragEvent, status: WorkspaceStatus) => void
}

function renderHostHeaderVirtualRow(
  ctx: WorktreeVirtualRowContext,
  row: Extract<RenderRow, { type: 'host-header' }>,
  vItem: VirtualItem
): React.JSX.Element {
  // Incoming hosts must cover the outgoing sticky group before they pin.
  const isActiveStickyHost = ctx.activeStickyHostIndexRef.current === vItem.index
  const hasHeaderTopSpacing = shouldUseHeaderTopSpacing({
    rows: ctx.renderRows,
    index: vItem.index,
    firstHeaderIndex: ctx.firstHeaderIndex
  })
  return (
    <div
      key={vItem.key}
      role="presentation"
      data-worktree-virtual-row
      data-worktree-virtual-row-key={String(vItem.key)}
      data-worktree-sticky-header=""
      data-worktree-sticky-header-active={isActiveStickyHost ? '' : undefined}
      data-glass-surface="worktree-sidebar"
      data-index={vItem.index}
      ref={ctx.measureVirtualRowElement}
      className={cn(
        'left-0 right-0 z-30 bg-worktree-sidebar',
        hasHeaderTopSpacing && !isActiveStickyHost && 'pt-1',
        isActiveStickyHost ? 'sticky -top-px' : 'absolute top-0'
      )}
      style={isActiveStickyHost ? undefined : { transform: getVirtualRowTransform(vItem.start) }}
    >
      <HostSectionHeader
        row={row}
        onToggle={() => ctx.toggleGroupWithScrollAnchor(row.key)}
        onDragPointerDown={
          ctx.orderedHostIds.length > 1
            ? (e) => ctx.hostDrag.onHandlePointerDown(e, row.hostId)
            : undefined
        }
        dragging={ctx.hostDrag.state.draggingHostId === row.hostId}
      />
    </div>
  )
}

function folderLineageToggle(
  ctx: WorktreeVirtualRowContext,
  row: { lineageGroupKey?: string }
): LineageToggleHandler | undefined {
  return row.lineageGroupKey ? ctx.item.getLineageToggleHandler(row.lineageGroupKey) : undefined
}

// Header frames retain sticky positioning; each workspace owns its measured slot.
export function renderWorktreeVirtualRow(
  ctx: WorktreeVirtualRowContext,
  row: RenderRow,
  vItem: VirtualItem,
  t?: Translate
): React.JSX.Element | null {
  if (row.type === 'host-header') {
    return renderHostHeaderVirtualRow(ctx, row, vItem)
  }
  const projectFrame = ctx.projectFrames?.get(vItem.index)

  if (row.type === 'header') {
    return renderWorktreeSectionHeaderRow(
      {
        ctx: ctx.header,
        row,
        vItem,
        isActiveStickyHeader: ctx.activeStickyHeaderIndexRef.current === vItem.index,
        hasStickyHost: ctx.activeStickyHostIndexRef.current !== null,
        hasHeaderTopSpacing: shouldUseHeaderTopSpacing({
          rows: ctx.renderRows,
          index: vItem.index,
          firstHeaderIndex: ctx.firstHeaderIndex
        }),
        measureVirtualRowElement: ctx.measureVirtualRowElement,
        projectFrame
      },
      t
    )
  }

  if (row.type === 'imported-worktrees-card') {
    return renderImportedWorktreesVirtualRow({
      row,
      vItem,
      measureVirtualRowElement: ctx.measureVirtualRowElement,
      actionStateByProjectId: ctx.importedWorktreeCardActionState,
      onShow: ctx.onShowImportedWorktrees,
      onKeepHidden: ctx.onKeepImportedWorktreesHidden,
      projectFrame
    })
  }

  if (row.type === 'new-external-worktrees-inbox') {
    return renderNewExternalWorktreesInboxVirtualRow({
      row,
      vItem,
      measureVirtualRowElement: ctx.measureVirtualRowElement,
      actionState: ctx.newExternalWorktreeInboxActionState.get(row.repo.id),
      onReview: ctx.onOpenWorktreeVisibility,
      onSuppress: ctx.onOpenSuppressExternalWorktreeInbox,
      projectFrame
    })
  }

  if (row.type === 'pending-creation') {
    return renderPendingCreationVirtualRow({
      row,
      vItem,
      measureVirtualRowElement: ctx.measureVirtualRowElement,
      projectFrame
    })
  }

  if (row.type === 'project-chats') {
    return renderProjectChatsVirtualRow({
      row,
      vItem,
      measureVirtualRowElement: ctx.measureVirtualRowElement,
      onCreateForRepo: ctx.header.projectActions.onCreateForRepo,
      onCreateFolderWorkspace: ctx.header.onCreateFolderWorkspace,
      projectFrame
    })
  }

  const frame = ctx.projection.frames[vItem.index]
  const lane = getTreeRowLane(projectFrame)
  const folder = row.type === 'folder-workspace'
  const itemWorkspaceStatus =
    !folder && ctx.groupBy === 'workspace-status'
      ? getWorkspaceStatus(row.worktree, ctx.workspaceStatuses)
      : null
  const itemKey = folder ? null : getWorktreeHostIdentity(row.worktree)
  const guidesInDraggedRange = ctx.hiddenDragRanges.some(
    ({ start, end }) => vItem.index >= start && vItem.index <= end
  )
  const sourceHidden =
    itemKey !== null && ctx.worktreeDragState.draggingWorktreeId !== null && guidesInDraggedRange
  const itemPreviewOffset =
    (itemKey
      ? ctx.worktreeDragState.previewOffsetsByWorktreeId.get(
          ctx.dragUnitsByRow.get(vItem.index)?.identity ?? itemKey
        )
      : 0) ?? 0
  const activeFamily = ctx.activeFamilyRoots.has(frame.root)
  const rootFrame = ctx.projection.frames[frame.root]
  // The root aligns to the project lane, and its descendants keep their relative indent.
  const shift = lane ? lane.surface - WORKTREE_CARD_SURFACE_MARGIN - rootFrame.left : 0
  const rowFrame = lane
    ? {
        ...frame,
        left: frame.left + shift,
        right: lane.right,
        contentIndent: Math.max(0, frame.contentIndent - TREE_CONTENT_PULLBACK)
      }
    : frame
  const familyHidden = ctx.hiddenDragRanges.some(
    ({ start, end }) => frame.root >= start && frame.root <= end
  )

  return (
    <div
      key={vItem.key}
      role="presentation"
      data-worktree-virtual-row
      data-worktree-virtual-row-key={String(vItem.key)}
      data-worktree-virtual-row-start={vItem.start}
      data-index={vItem.index}
      ref={ctx.measureVirtualRowElement}
      data-workspace-status-drop-target={itemWorkspaceStatus ? '' : undefined}
      data-workspace-status={itemWorkspaceStatus ?? undefined}
      className={cn(
        'absolute left-0 right-0 top-0',
        activeFamily && frame.root === vItem.index && 'worktree-sidebar-family-root',
        ctx.worktreeDragState.draggingWorktreeId !== null &&
          'transition-transform duration-150 ease-out will-change-transform'
      )}
      style={{
        transform: getWorktreeVirtualRowTransform(vItem.start, itemPreviewOffset)
      }}
      onDragOver={
        itemWorkspaceStatus
          ? (event) => ctx.onWorkspaceStatusDragOver(event, itemWorkspaceStatus)
          : undefined
      }
      onDragLeave={itemWorkspaceStatus ? ctx.onWorkspaceStatusDragLeave : undefined}
      onDrop={
        itemWorkspaceStatus
          ? (event) => ctx.onWorkspaceStatusDrop(event, itemWorkspaceStatus)
          : undefined
      }
    >
      <ProjectFrameEdge piece={projectFrame} gapInside />
      <div
        className="relative"
        data-worktree-lineage-row={frame.guides ? '' : undefined}
        style={{ paddingTop: frame.before, paddingBottom: frame.closing + frame.after }}
      >
        {frame.guides && (
          <LineageGuides
            guides={frame.guides}
            before={frame.before}
            height={vItem.size}
            xOffset={shift}
            hidden={guidesInDraggedRange || familyHidden}
          />
        )}
        <div className={cn('relative', sourceHidden && 'pointer-events-none opacity-0')}>
          <SidebarNumberHintBadge
            hintKey={workspaceRowNumberHintKey(
              folder ? getFolderWorkspaceHostIdentity(row.folderWorkspace) : row.rowKey
            )}
          />
          {folder
            ? renderFolderWorkspaceOption({
                ctx: ctx.folderWorkspace,
                row,
                frame: rowFrame,
                lineage: { onToggle: folderLineageToggle(ctx, row), childIsActive: activeFamily }
              })
            : renderWorktreeItemRow(
                ctx.item,
                row,
                rowFrame,
                activeFamily && frame.root === vItem.index
              )}
        </div>
      </div>
    </div>
  )
}

/** Paint one continuous backdrop per visible active family so virtual row boundaries never show seams. */
export function renderActiveFamilyBackdrops(
  ctx: WorktreeVirtualRowContext,
  virtualItems: readonly VirtualItem[]
): React.JSX.Element[] | null {
  if (ctx.activeFamilyRoots.size === 0 || virtualItems.length === 0) {
    return null
  }
  const backdrops: React.JSX.Element[] = []
  for (const root of ctx.activeFamilyRoots) {
    const rootFrame = ctx.projection.frames[root]
    const rootRow = ctx.renderRows[root]
    if (!rootFrame || !rootRow) {
      continue
    }
    let first: VirtualItem | null = null
    let last: VirtualItem | null = null
    for (const vItem of virtualItems) {
      if (vItem.index < root) {
        continue
      }
      if (vItem.index > rootFrame.end) {
        break
      }
      if (!first) {
        first = vItem
      }
      last = vItem
    }
    if (!first || !last) {
      continue
    }
    const lane = getTreeRowLane(ctx.projectFrames?.get(root))
    const isClosed = rootFrame.end === root
    const includesTop = first.index === root
    const includesBottom = last.index === rootFrame.end
    const lastFrame = ctx.projection.frames[last.index]
    const top = first.start
    const height = Math.max(0, last.end - top - (includesBottom ? lastFrame.after : 0))
    const familyHidden = ctx.hiddenDragRanges.some(({ start, end }) => root >= start && root <= end)
    const rootKey = rootRow.type === 'item' ? getWorktreeHostIdentity(rootRow.worktree) : null
    const rootPreviewOffset =
      (rootKey
        ? ctx.worktreeDragState.previewOffsetsByWorktreeId.get(
            ctx.dragUnitsByRow.get(root)?.identity ?? rootKey
          )
        : 0) ?? 0
    const familyVariant =
      rootRow.type === 'item' &&
      isActiveSidebarWorkspace(rootRow.worktree, {
        worktreeId: ctx.item.activeWorktreeId,
        hostId: ctx.item.activeWorkspaceExecutionHostId
      })
        ? ctx.item.getActiveSurfaceVariant(rootRow)
        : 'primary'
    backdrops.push(
      <div
        key={`family-backdrop:${getRenderRowKey(rootRow)}`}
        aria-hidden="true"
        data-worktree-family-segment={familyVariant}
        data-worktree-family-closed={isClosed ? '' : undefined}
        className={cn(
          'pointer-events-none absolute top-0 border-x',
          familyHidden && 'opacity-0',
          includesTop && 'rounded-t-lg border-t',
          includesBottom && 'rounded-b-lg border-b',
          ctx.worktreeDragState.draggingWorktreeId !== null &&
            'transition-transform duration-150 ease-out will-change-transform'
        )}
        style={{
          left: lane ? lane.surface - WORKTREE_CARD_SURFACE_MARGIN + 4 : rootFrame.left + 4,
          right: lane?.right ?? rootFrame.right,
          height,
          transform: getWorktreeVirtualRowTransform(top, rootPreviewOffset)
        }}
      />
    )
  }
  return backdrops.length > 0 ? backdrops : null
}

export function renderWorktreeVirtualRows(
  ctx: WorktreeVirtualRowContext,
  virtualItems: readonly VirtualItem[],
  t?: Translate
): React.JSX.Element {
  return (
    <>
      {renderActiveFamilyBackdrops(ctx, virtualItems)}
      {virtualItems.map((vItem) => {
        const row = ctx.renderRows[vItem.index]
        return row ? renderWorktreeVirtualRow(ctx, row, vItem, t) : null
      })}
    </>
  )
}
