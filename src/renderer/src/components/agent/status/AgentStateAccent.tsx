import { cn } from '@/lib/class-names'
import type { AgentDotState } from './AgentStateDot'

function agentStateAccentTone(state: AgentDotState | null, unread: boolean): string | undefined {
  switch (state) {
    case 'permission':
    case 'blocked':
    case 'waiting':
      return 'bg-agent-question'
    case 'failed':
      return 'bg-red-500'
    case 'working':
    case 'monitoring':
      return 'bg-agent-working'
    case 'done':
      return unread ? 'bg-unread' : 'bg-emerald-500'
    case 'idle':
    case 'interrupted':
    case 'unconfirmed':
    case 'unverifiable':
    case null:
      return unread ? 'bg-unread' : undefined
  }
}

export function AgentStateAccent({
  state,
  unread = false,
  manualColor,
  edge = 'start'
}: {
  state: AgentDotState | null
  unread?: boolean
  manualColor?: string | null
  edge?: 'start' | 'end'
}): React.JSX.Element | null {
  const tone = manualColor ? undefined : agentStateAccentTone(state, unread)
  if (!tone && !manualColor) {
    return null
  }
  return (
    <span
      data-agent-state-accent=""
      aria-hidden
      className={cn(
        'pointer-events-none absolute inset-y-1 w-0.5 rounded-full forced-colors:hidden',
        edge === 'end' ? 'end-0' : 'start-0',
        tone
      )}
      style={manualColor ? { backgroundColor: manualColor } : undefined}
    />
  )
}
