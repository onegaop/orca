import { useCallback, useContext, useSyncExternalStore } from 'react'
import { useNativeChatPaneLifetimeEffect } from '../ownership/native-chat-pane-lifetime'
import { NativeChatViewTabContext } from '../ownership/native-chat-view-memory'

const EMPTY: ReadonlySet<string> = new Set()

/**
 * Only shown chats and chats with an open annotation stay mounted. Each change wakes only the tabs whose
 * membership changed.
 */
class ChatViewRetention {
  private shownByLayer = new Map<string, readonly string[]>()
  private annotationHolds = new Map<string, number>()
  private retained: ReadonlySet<string> = EMPTY
  private listenersByTab = new Map<string, Set<() => void>>()

  /** A layer reports the chats it shows now; an empty list hides them all. */
  show(layer: string, tabIds: readonly string[]): void {
    if (tabIds.length === 0) {
      this.shownByLayer.delete(layer)
    } else {
      this.shownByLayer.set(layer, tabIds)
    }
    this.recompute()
  }

  holdAnnotation(tabId: string): () => void {
    const holds = this.annotationHolds
    holds.set(tabId, (holds.get(tabId) ?? 0) + 1)
    this.recompute()
    return () => {
      const count = (holds.get(tabId) ?? 1) - 1
      if (count > 0) {
        holds.set(tabId, count)
      } else {
        holds.delete(tabId)
      }
      this.recompute()
    }
  }

  private recompute(): void {
    const shown = new Set([...this.shownByLayer.values()].flat())
    const next = new Set([...shown, ...this.annotationHolds.keys()])
    const previous = this.retained
    this.retained = next
    const notify = new Set<() => void>()
    for (const id of next) {
      if (!previous.has(id)) {
        this.listenersByTab.get(id)?.forEach((listener) => notify.add(listener))
      }
    }
    for (const id of previous) {
      if (!next.has(id)) {
        this.listenersByTab.get(id)?.forEach((listener) => notify.add(listener))
      }
    }
    notify.forEach((listener) => listener())
  }

  subscribe(tabIds: ReadonlySet<string>, listener: () => void): () => void {
    for (const id of tabIds) {
      let listeners = this.listenersByTab.get(id)
      if (!listeners) {
        listeners = new Set()
        this.listenersByTab.set(id, listeners)
      }
      listeners.add(listener)
    }
    return () => {
      for (const id of tabIds) {
        const listeners = this.listenersByTab.get(id)
        listeners?.delete(listener)
        if (listeners?.size === 0) {
          this.listenersByTab.delete(id)
        }
      }
    }
  }

  /** The retained tabs among `tabIds`, walking only the small retained set. */
  retainedAmong(tabIds: ReadonlySet<string>): string {
    return [...this.retained]
      .filter((id) => tabIds.has(id))
      .sort()
      .join('\n')
  }
}

export const chatViewRetention = new ChatViewRetention()

/** This layer's retained tabs as a stable key; only a change to one of its own tabs wakes it. */
export function useRetainedChatViewKey(ownedTabIds: ReadonlySet<string>): string {
  const subscribe = useCallback(
    (listener: () => void) => chatViewRetention.subscribe(ownedTabIds, listener),
    [ownedTabIds]
  )
  return useSyncExternalStore(subscribe, () => chatViewRetention.retainedAmong(ownedTabIds))
}

/** The viewer's unfinished note and undo history can't be reconstructed from a chat draft. */
export function useNativeChatAnnotationViewHold(editing: boolean): void {
  const tab = useContext(NativeChatViewTabContext)
  useNativeChatPaneLifetimeEffect(
    useCallback(
      () => (editing && tab ? chatViewRetention.holdAnnotation(tab.tabId) : undefined),
      [editing, tab]
    )
  )
}
