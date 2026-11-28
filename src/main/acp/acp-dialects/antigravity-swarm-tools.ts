import { z } from 'zod'
import { lazyZodSchema } from '../../../shared/schema/lazy-zod-schema'
import type { ToolCallUpdate } from '../generated/acp-protocol.generated'

const SWARM_TOOL_NAME =
  /^(swarm_post_message|swarm_read_board|swarm_wait|swarm|invoke_subagent)(?=$|[\s:(])/

const swarmInputSchema = lazyZodSchema(() =>
  z.looseObject({
    action: z.string().optional(),
    name: z.string().optional(),
    role: z.string().optional()
  })
)

export function swarmToolName(update: ToolCallUpdate): string | undefined {
  if (update.kind === 'execute') {
    return 'execute'
  }
  const title = update.title?.trim()
  return title ? SWARM_TOOL_NAME.exec(title)?.[1] : undefined
}

export function antigravityToolSubagents(
  update: ToolCallUpdate,
  tool: { name?: string; input?: unknown; state?: string }
) {
  if (tool.name !== 'swarm') {
    return []
  }
  const parsed = swarmInputSchema.safeParse(tool.input ?? update.rawInput).data
  const name = parsed?.name?.trim()
  if (!name) {
    return []
  }
  if (parsed?.action === 'add') {
    const failed = update.status === 'failed' || tool.state === 'failed'
    return [{ id: name, label: name, state: failed ? ('failed' as const) : ('working' as const) }]
  }
  if (parsed?.action === 'kill' && (update.status === 'completed' || tool.state === 'completed')) {
    return [{ id: name, state: 'stopped' as const }]
  }
  return []
}
