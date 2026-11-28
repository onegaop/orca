import type { AgentStatusState } from '../../../agent-status/contracts/agent-status-types'
import { isRecord } from '../../../agent-status/child-work/agent-status-child-work-value-guards'
import { readFirstString } from '../../interactive-tool'
import type { HookListenerState } from '../../listener-state'
import { extractToolFields } from '../../provider-event-routing'
import { readAntigravityToolCall } from './antigravity-tool-fields'
import {
  createAntigravityBrainCache,
  normalizeAntigravityModel,
  readAntigravityChildStartedAt,
  readAntigravityChildTranscriptTail,
  readAntigravityTranscriptModel,
  type AntigravityBrainCache
} from './antigravity-brain-metadata'
import { isAntigravityFeedbackTool, isAntigravityStopStillBusy } from './antigravity-event-rules'

export type TrackedAntigravityChild = {
  id: string
  startedAt: number
  hookState?: 'working' | 'waiting' | 'done'
  sawToolHook?: boolean
  hookStepIdx?: number
  settledStepAtTurnStart?: number
  lastMemberWakeMode?: string
  lastMemberModel?: string
  hookModel?: string
  fallbackModel?: string
  toolName?: string
  toolInput?: string
}

export type AntigravityPaneChildState = {
  rootConversationId?: string
  rootBrainDir?: string
  awaitingInitialHelperDiscovery?: boolean
  leadState?: AgentStatusState
  leadStateStartedAt?: number
  leadModel?: string
  commands?: Set<string>
  helpersIdleAt?: number
  children: Map<string, TrackedAntigravityChild>
  brainCache: AntigravityBrainCache
}

export function getOrCreateAntigravityPaneState(
  state: HookListenerState,
  paneKey: string
): AntigravityPaneChildState {
  let existing = state.antigravityChildWorkByPaneKey.get(paneKey)
  if (!existing) {
    existing = {
      children: new Map(),
      brainCache: createAntigravityBrainCache()
    }
    state.antigravityChildWorkByPaneKey.set(paneKey, existing)
  }
  return existing
}

export function getOrCreateTrackedChild(
  paneState: AntigravityPaneChildState,
  childId: string,
  startedAt: number
): TrackedAntigravityChild {
  let tracked = paneState.children.get(childId)
  if (!tracked) {
    tracked = { id: childId, startedAt }
    paneState.children.set(childId, tracked)
  }
  return tracked
}

export function recordAntigravityChildHook(
  paneState: AntigravityPaneChildState,
  childId: string,
  eventName: unknown,
  hookPayload: Record<string, unknown>,
  transcriptPath: string | undefined,
  now: number
): void {
  paneState.awaitingInitialHelperDiscovery = false
  const initialStart =
    paneState.children.get(childId)?.startedAt ??
    (paneState.rootBrainDir
      ? readAntigravityChildStartedAt(paneState.rootBrainDir, childId)
      : undefined) ??
    now
  const tracked = getOrCreateTrackedChild(paneState, childId, initialStart)
  const hookModel = normalizeAntigravityModel(readFirstString(hookPayload, ['modelName', 'model']))
  if (hookModel) {
    tracked.hookModel = hookModel
  } else if (!tracked.hookModel && !tracked.fallbackModel && transcriptPath) {
    tracked.fallbackModel = readAntigravityTranscriptModel(transcriptPath)
  }
  if (typeof hookPayload.stepIdx === 'number') {
    tracked.hookStepIdx = hookPayload.stepIdx
  }

  if (eventName === 'PreInvocation' || eventName === 'PostInvocation') {
    if (eventName === 'PreInvocation') {
      tracked.toolName = undefined
      tracked.toolInput = undefined
      if (paneState.rootBrainDir) {
        const tail = readAntigravityChildTranscriptTail(paneState.rootBrainDir, childId)
        tracked.settledStepAtTurnStart = tail?.settled ? tail.stepIndex : undefined
      }
    }
    tracked.hookState = 'working'
    return
  }
  if (eventName === 'PreToolUse') {
    const tool = extractToolFields('antigravity', 'PreToolUse', hookPayload)
    tracked.sawToolHook = true
    tracked.toolName = tool.toolName
    tracked.toolInput = tool.toolInput
    tracked.hookState = isAntigravityFeedbackTool(tool.toolName) ? 'waiting' : 'working'
    return
  }
  if (eventName === 'PostToolUse') {
    tracked.sawToolHook = true
    tracked.toolName = undefined
    tracked.toolInput = undefined
    tracked.hookState = 'working'
    return
  }
  if (eventName === 'Stop') {
    tracked.toolName = undefined
    tracked.toolInput = undefined
    tracked.hookState = isAntigravityStopStillBusy(hookPayload) ? 'working' : 'done'
  }
}

/** agy sends a backgrounded run_command's PostToolUse only when the command ends; daemons are never expected to. */
export function trackAntigravityBackgroundCommand(
  paneState: AntigravityPaneChildState,
  eventName: unknown,
  conversationId: string | undefined,
  hookPayload: Record<string, unknown>
): boolean {
  const { toolName, toolInputSource } = readAntigravityToolCall(hookPayload)
  const stepIdx = hookPayload.stepIdx
  if (
    toolName !== 'run_command' ||
    !conversationId ||
    typeof stepIdx !== 'number' ||
    (eventName !== 'PreToolUse' && eventName !== 'PostToolUse')
  ) {
    return false
  }
  const key = `${conversationId}:${stepIdx}`
  if (eventName === 'PostToolUse') {
    return paneState.commands?.delete(key) === true
  }
  if (isRecord(toolInputSource) && toolInputSource.IsDaemon === true) {
    return false
  }
  paneState.commands = (paneState.commands ?? new Set()).add(key)
  return false
}
