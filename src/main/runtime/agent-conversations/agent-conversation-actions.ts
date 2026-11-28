import { randomUUID } from 'node:crypto'
import {
  AGENT_CONVERSATION_REFUSAL_CODES as CODES,
  type AgentPendingPrompt,
  type AgentReplyResult,
  type AgentRequestsResult,
  type AgentRespondResult
} from '../../../shared/agent-conversations/agent-conversation-contracts'
import {
  createStructuredAgentSessionOperationId,
  structuredAgentSessionPayloadFingerprint
} from '../../../shared/agent-session/lifecycle/operations/structured-agent-session-mutation'
import {
  structuredAgentSessionMessageSendMutation,
  structuredAgentSessionSendBody
} from '../../../shared/agent-session/requests/structured-agent-session-send-mutation'
import type { AgentJournalPromptOption } from '../../../shared/agent-session/journal/agent-session-journal-types'
import { agentSessionSendSubmission } from '../../../shared/agent-session/agent-session-wire'
import type { RpcContext } from '../rpc/core'
import {
  requireInstalledStructuredHost,
  requireStructuredAgentAudience,
  structuredCallerFor
} from '../rpc/methods/structured-sessions/creation/structured-agent-session-gate'
import { resolveLineageRunningSession } from '../orchestration/addressing/session-lineage/structured-session-lineage'
import type { ResolvedAgentConversation } from './agent-conversation-address'
import { AgentConversationRefusal } from './agent-conversation-refusal'

function resolveActiveChatSession(
  ctx: RpcContext,
  resolved: ResolvedAgentConversation,
  actionName: string
) {
  if (resolved.kind !== 'chat') {
    throw new AgentConversationRefusal(
      CODES.unavailable,
      `Agent ${resolved.orcaSessionId} is a terminal agent; ${actionName} is supported for structured chats. Open it in Orca to interact directly.`
    )
  }
  const { record, store, orcaSessionId } = resolved
  requireStructuredAgentAudience(ctx, record.provider)
  const running = resolveLineageRunningSession(store, record.sessionId)
  if (running.kind === 'other-host') {
    throw new AgentConversationRefusal(
      CODES.unavailable,
      `Agent ${orcaSessionId} runs on another host. Pass \`--environment <host>\`.`
    )
  }
  if (running.kind === 'unverifiable') {
    throw new AgentConversationRefusal(
      CODES.unavailable,
      `Orca can't verify agent ${orcaSessionId}'s active chat after /clear. Open it in Orca first.`
    )
  }
  const activeRecord = store.getRecord(running.sessionId)
  return {
    orcaSessionId,
    sessionId: running.sessionId,
    runtimeFence: activeRecord?.currentFence ?? 1
  }
}

function mapOptionKind(option: AgentJournalPromptOption): string | undefined {
  if (option.intent === 'reject_once' || option.intent === 'reject_always') {
    return 'reject'
  }
  if (option.intent === 'allow_once' || option.intent === 'allow_always') {
    return 'allow'
  }
  return undefined
}

export async function readAgentPendingRequests(
  ctx: RpcContext,
  resolved: ResolvedAgentConversation
): Promise<AgentRequestsResult> {
  if (resolved.kind !== 'chat') {
    return { orcaSessionId: resolved.orcaSessionId, prompts: [] }
  }
  const { orcaSessionId, sessionId } = resolveActiveChatSession(ctx, resolved, 'reading requests')
  const host = await requireInstalledStructuredHost(ctx, sessionId)
  const [work, history] = await Promise.all([
    host.currentWorkAtRest(sessionId),
    host.history({ sessionId, direction: 'tail', limit: 60 })
  ])
  const actionable = work ? new Set(work.actionablePromptIds()) : null
  const prompts: AgentPendingPrompt[] = []
  for (const item of history.page.items) {
    if (
      (item.body.kind !== 'approval' && item.body.kind !== 'question') ||
      item.body.resolution.state !== 'pending'
    ) {
      continue
    }
    if (actionable && !actionable.has(item.itemId)) {
      continue
    }
    if (item.body.kind === 'approval') {
      prompts.push({
        itemId: item.itemId,
        revision: item.revision,
        kind: 'approval',
        title: item.body.displayName ?? item.body.title,
        ...(item.body.detail ? { detail: item.body.detail } : {}),
        options: item.body.options.map((option) => {
          const kind = mapOptionKind(option)
          return { id: option.id, label: option.label, ...(kind ? { kind } : {}) }
        })
      })
    } else {
      const firstQuestion = item.body.questions?.[0]
      const rawOptions = firstQuestion?.options ?? item.body.options
      prompts.push({
        itemId: item.itemId,
        revision: item.revision,
        kind: 'question',
        title: firstQuestion?.question ?? item.body.question,
        ...(firstQuestion?.id ? { questionId: firstQuestion.id } : {}),
        options: rawOptions.map((option) => ({ id: option.id, label: option.label }))
      })
    }
  }
  return { orcaSessionId, prompts }
}

export async function replyToAgentConversation(
  ctx: RpcContext,
  resolved: ResolvedAgentConversation,
  text: string
): Promise<AgentReplyResult> {
  const { orcaSessionId, sessionId, runtimeFence } = resolveActiveChatSession(
    ctx,
    resolved,
    'replying'
  )
  const host = await requireInstalledStructuredHost(ctx, sessionId)
  const body = structuredAgentSessionSendBody(text, [])
  const mutation = structuredAgentSessionMessageSendMutation({
    sessionId,
    clientOperationId: createStructuredAgentSessionOperationId(() => randomUUID()),
    expectedRuntimeFence: runtimeFence,
    body,
    delivery: 'queue-if-active'
  })
  const result = await host.send(structuredCallerFor(ctx), { ...mutation, userSend: true })
  if (!result.ok) {
    throw new AgentConversationRefusal(
      CODES.unavailable,
      result.refusal.message || 'Orca could not send that reply to the chat.'
    )
  }
  const submission = agentSessionSendSubmission(result.value)
  return {
    orcaSessionId,
    accepted: true,
    ...(submission?.dispatchState ? { dispatchState: submission.dispatchState } : {})
  }
}

export async function respondToAgentConversationPrompt(
  ctx: RpcContext,
  resolved: ResolvedAgentConversation,
  params: {
    itemId: string
    revision: number
    kind: 'approval' | 'question'
    optionId: string
    questionId?: string
  }
): Promise<AgentRespondResult> {
  const { orcaSessionId, sessionId, runtimeFence } = resolveActiveChatSession(
    ctx,
    resolved,
    'responding to prompts'
  )
  const host = await requireInstalledStructuredHost(ctx, sessionId)
  const answers =
    params.kind === 'question' && params.questionId
      ? [{ questionId: params.questionId, optionIds: [params.optionId] }]
      : undefined
  const fields = {
    itemId: params.itemId,
    expectedRevision: params.revision,
    ...(answers ? { answers } : { optionId: params.optionId })
  }
  const envelope = {
    sessionId,
    clientOperationId: createStructuredAgentSessionOperationId(() => randomUUID()),
    expectedRuntimeFence: runtimeFence,
    payloadFingerprint: structuredAgentSessionPayloadFingerprint({
      method: `agentSession.respondTo:${params.kind}`,
      sessionId,
      fields
    })
  }
  const result = await host.respondToPrompt(structuredCallerFor(ctx), {
    envelope,
    kind: params.kind,
    ...fields
  })
  if (!result.ok) {
    throw new AgentConversationRefusal(
      CODES.unavailable,
      result.refusal.message || 'Orca could not submit that prompt response.'
    )
  }
  return {
    orcaSessionId,
    itemId: params.itemId,
    resolved: true
  }
}
