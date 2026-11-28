import React, { useMemo } from 'react'
import { useTabStripOverflowNavigation } from './strip/tab-strip-overflow-navigation'
import { useTabStripDragScrollHandlers } from './strip/tab-strip-drag-scroll'
import type { TabBarProps } from './tab-bar-props'
import { renderTabBarSurface } from './strip/tab-bar-surface'
import { useTranslate } from '@/i18n/use-translate'
import { useTabStripScrollMemory } from './strip/tab-strip-scroll-memory'
import { resolveRenderedTabStrip } from './strip/rendered-tab-strip'
import { useTabBarModel, type TabBarModel } from './model/use-tab-bar-model'
import { useTabBarRuntimeModel } from './model/use-tab-bar-runtime-model'
import VerticalTabBar from './vertical/VerticalTabBar'

function HorizontalTabBar({
  props,
  model
}: {
  props: TabBarProps
  model: TabBarModel
}): React.JSX.Element {
  const t = useTranslate()
  const { worktreeId, groupId } = props
  const {
    itemProjection,
    pinnedSortableIds,
    stripSortableIds,
    clientHostedBrowserRows,
    activeClientHostedBrowserRowId
  } = model
  const slotIds = useMemo(
    () => [...stripSortableIds, ...clientHostedBrowserRows.map((row) => row.browserPageId)],
    [clientHostedBrowserRows, stripSortableIds]
  )
  // Why memoized: the key spans every tab, and a windowed strip re-renders as it scrolls.
  const stripLayoutKey = useMemo(
    () =>
      [
        itemProjection.tabStripLayoutKey,
        ...clientHostedBrowserRows.map((row) => row.browserPageId)
      ].join('|'),
    [clientHostedBrowserRows, itemProjection.tabStripLayoutKey]
  )
  const tabStripNavigation = useTabStripOverflowNavigation({
    activeVisibleTabId: itemProjection.activeVisibleTabId,
    activeDockSlotId: activeClientHostedBrowserRowId ?? itemProjection.activeVisibleTabId,
    isFocused: props.isFocused,
    layoutKey: stripLayoutKey,
    slotIds,
    worktreeId
  })
  useTabStripScrollMemory(
    groupId,
    worktreeId,
    tabStripNavigation.tabStripRef,
    itemProjection.activeVisibleTabId
  )
  const tabStripDragScroll = useTabStripDragScrollHandlers(tabStripNavigation.scrollTabStrip, {
    start: tabStripNavigation.tabStripOverflowState.canScrollStart,
    end: tabStripNavigation.tabStripOverflowState.canScrollEnd
  })

  return renderTabBarSurface(
    {
      props,
      runtime: model.runtime,
      createMenu: model.createMenu,
      itemProjection,
      strip: resolveRenderedTabStrip({
        itemProjection,
        pinnedSortableIds,
        stripSortableIds,
        clientHostedBrowserRows
      }),
      tabStripNavigation,
      tabStripDragScroll,
      activeClientHostedBrowserRowId,
      itemActions: model.itemActions,
      surfaceRef: model.surfaceRef,
      bot: model.bot,
      botGroup: model.botGroup
    },
    t
  )
}

function TabBarInner(props: TabBarProps): React.JSX.Element {
  const runtime = useTabBarRuntimeModel({ worktreeId: props.worktreeId, groupId: props.groupId })
  const model = useTabBarModel(props, runtime)
  // Why two components: each orientation owns its scroller hooks, and switching remounts cleanly.
  return props.orientation === 'vertical' ? (
    <VerticalTabBar props={props} model={model} />
  ) : (
    <HorizontalTabBar props={props} model={model} />
  )
}

export default React.memo(TabBarInner)
