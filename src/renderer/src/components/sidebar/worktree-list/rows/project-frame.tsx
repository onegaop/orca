import React, { useMemo } from 'react'
import { cn } from '@/lib/class-names'
import { useAppStore } from '@/store/index'
import type { HostSectionRow } from '../../../../../../shared/sidebar-list/hosts/host-section-rows'
import { isProjectTreeOn } from '../../../../../../shared/sidebar-list/project-tree-settings'
import { getRepoIdFromWorktreeId } from '../../../../../../shared/worktree/id'
import { MAX_PROJECT_GROUP_HEADER_DEPTH, PROJECT_GROUP_HEADER_BASE_PADDING } from './indentation'
import { shouldUseHeaderTopSpacing } from '../viewport/virtual-rows'

/** Tree style only. Headers, workspace rows and guides share one 16px grid. */
const TREE_STEP = 16
const TREE_GLYPH_INSET = 10
const TREE_RIGHT_INSET = 2

export type ProjectFramePiece = {
  project?: { depth: number; current: boolean }
  guides: readonly number[]
  startGuides?: readonly number[]
  endGuides?: readonly number[]
  separated?: boolean
}

/** The height a separated header adds (its top padding grows from 4px to 12px). */
export const TREE_SEPARATOR_SPACE = 8

/** A top-level group or project with something above it in its host section. */
export function isSeparatedTreeHeader(
  rows: readonly HostSectionRow[],
  index: number,
  firstHeaderIndex: number
): boolean {
  const row = rows[index]
  return (
    row?.type === 'header' &&
    (row.projectGroupDepth ?? 0) === 0 &&
    rows[index - 1]?.type !== 'host-header' &&
    // The extra room extends the header's own top spacing, so both follow one rule.
    shouldUseHeaderTopSpacing({ rows, index, firstHeaderIndex })
  )
}

/** A Tree workspace or session row is one line: its height before the 6px gap it carries. */
export const TREE_LINE_ROW_HEIGHT = 24

function hasTreeLane(row: HostSectionRow): boolean {
  return row.type === 'item' || row.type === 'folder-workspace' || row.type === 'project-chats'
}

/** The displayed rows already encode collapse and host grouping. Draw only their shared hierarchy. */
export function computeProjectFrames(
  rows: readonly HostSectionRow[],
  activeRepoId: string | null
): ReadonlyMap<number, ProjectFramePiece> {
  const pieces = new Map<number, ProjectFramePiece>()
  const firstHeaderIndex = rows.findIndex(
    (row) => row.type === 'header' || row.type === 'host-header'
  )
  let openGroups: number[] = []
  let project: ProjectFramePiece['project']
  rows.forEach((row, index) => {
    if (row.type === 'host-header') {
      openGroups = []
      project = undefined
      return
    }
    if (row.type === 'header') {
      const depth = row.projectGroupDepth ?? 0
      openGroups = openGroups.filter((open) => open < depth)
      project = row.repo ? { depth, current: row.repo.id === activeRepoId } : undefined
      pieces.set(index, {
        guides: openGroups,
        project,
        separated: isSeparatedTreeHeader(rows, index, firstHeaderIndex)
      })
      if (row.projectGroup && !row.repo) {
        openGroups = [...openGroups, depth]
      }
      return
    }
    if (hasTreeLane(row)) {
      pieces.set(index, { guides: project ? [...openGroups, project.depth] : openGroups, project })
    }
  })
  for (const [index, piece] of pieces) {
    const previousGuides = pieces.get(index - 1)?.guides ?? []
    const nextGuides = pieces.get(index + 1)?.guides ?? []
    piece.startGuides = piece.guides.filter((depth) => !previousGuides.includes(depth))
    piece.endGuides = piece.guides.filter((depth) => !nextGuides.includes(depth))
  }
  return pieces
}

export function useProjectFrames(
  rows: readonly HostSectionRow[],
  activeWorktreeId: string | null
): ReadonlyMap<number, ProjectFramePiece> | undefined {
  const enabled = useAppStore((s) => isProjectTreeOn(s.settings))
  const activeRepoId = activeWorktreeId ? getRepoIdFromWorktreeId(activeWorktreeId) : null
  return useMemo(
    () => (enabled ? computeProjectFrames(rows, activeRepoId) : undefined),
    [enabled, rows, activeRepoId]
  )
}

export function getProjectTreeHeaderInset(depth: number): number {
  return (
    PROJECT_GROUP_HEADER_BASE_PADDING + Math.min(depth, MAX_PROJECT_GROUP_HEADER_DEPTH) * TREE_STEP
  )
}

/** Keep the active/hover treatment on a single project header rather than boxing every subtree. */
export function getTreeCardInset(depth: number): { left: number; right: number } {
  return { left: getProjectTreeHeaderInset(depth) - 6, right: TREE_RIGHT_INSET }
}

/** A child begins exactly one tree step to the right of the parent's disclosure chevron. */
export function getTreeChildLane(depth: number): { surface: number; right: number; glyph: number } {
  const glyph = getProjectTreeHeaderInset(depth) + TREE_STEP + 2
  return { surface: glyph - TREE_GLYPH_INSET, right: TREE_RIGHT_INSET, glyph }
}

export function getTreeRowLane(
  piece: ProjectFramePiece | undefined
): ReturnType<typeof getTreeChildLane> | null {
  const depth = piece?.project?.depth ?? piece?.guides.at(-1)
  return depth === undefined ? null : getTreeChildLane(depth)
}

export function ProjectFrameEdge({
  piece,
  gapInside = false
}: {
  piece: ProjectFramePiece | undefined
  /** Workspace rows carry the 6px gap in their own height. */
  gapInside?: boolean
}): React.JSX.Element | null {
  if (!piece) {
    return null
  }
  const bridge = gapInside ? 'bottom-0' : '-bottom-1.5'
  return (
    <>
      {piece.guides.map((depth) => (
        <TreeIndentGuide
          key={depth}
          depth={depth}
          startsHere={piece.startGuides?.includes(depth)}
          bridge={piece.endGuides?.includes(depth) ? 'bottom-2.5' : bridge}
        />
      ))}
    </>
  )
}

function TreeIndentGuide({
  depth,
  bridge,
  startsHere = false
}: {
  depth: number
  bridge: string
  startsHere?: boolean
}): React.JSX.Element {
  // The 12px disclosure chevron is centered on the rail; guides begin on the first child row to clear the header pill.
  return (
    <span
      aria-hidden="true"
      data-project-tree-indent-guide=""
      className={cn(
        'pointer-events-none absolute w-px bg-worktree-sidebar-foreground/20',
        startsHere ? 'top-1' : 'top-0',
        bridge
      )}
      style={{ insetInlineStart: getProjectTreeHeaderInset(depth) + 6 }}
    />
  )
}
