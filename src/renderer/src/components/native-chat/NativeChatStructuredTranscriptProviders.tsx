import type { ComponentProps } from 'react'
import type { NativeChatStructuredViewProps } from './native-chat-view-types'
import { NativeChatSubagentTranscripts } from './subagents/NativeChatSubagentTranscripts'
import { NativeChatRowActionsProvider } from './messages/actions/NativeChatRowActionsProvider'
import { NativeChatUsageLimitActionsProvider } from './usage/NativeChatUsageLimitActions'
import { NativeChatHostSetupContext } from './host-access/native-chat-host-setup'
import {
  NativeChatWorkerApprovalTimeline,
  nativeChatWorkerApprovalParty
} from './worker-approvals/NativeChatWorkerApprovals'

type TranscriptProps = ComponentProps<typeof NativeChatSubagentTranscripts>
type RowActionsProps = ComponentProps<typeof NativeChatRowActionsProvider>
type UsageLimitProps = ComponentProps<typeof NativeChatUsageLimitActionsProvider>
type HostSetupValue = ComponentProps<typeof NativeChatHostSetupContext.Provider>['value']

export function NativeChatStructuredTranscriptProviders({
  pane,
  chat,
  forks,
  recovery,
  directory,
  messages,
  view,
  setup,
  messageListRef,
  transcriptKey,
  transcriptProps
}: {
  pane: Omit<NativeChatStructuredViewProps, 'mode'>
  chat: RowActionsProps['chat']
  forks: RowActionsProps['forks']
  recovery: UsageLimitProps['recovery']
  directory: UsageLimitProps['directory']
  messages: UsageLimitProps['messages']
  view: UsageLimitProps['view']
  setup: HostSetupValue
  messageListRef: TranscriptProps['ref']
  transcriptKey: string
  transcriptProps: Omit<TranscriptProps, 'timedRows'>
}): React.JSX.Element {
  return (
    <NativeChatRowActionsProvider pane={pane} chat={chat} forks={forks}>
      <NativeChatUsageLimitActionsProvider
        recovery={recovery}
        pane={pane}
        directory={directory}
        messages={messages}
        view={view}
      >
        <NativeChatHostSetupContext.Provider value={setup}>
          <NativeChatWorkerApprovalTimeline
            party={nativeChatWorkerApprovalParty(pane)}
            target={pane.target}
          >
            {(timedRows) => (
              <NativeChatSubagentTranscripts
                key={transcriptKey}
                ref={messageListRef}
                {...transcriptProps}
                timedRows={timedRows}
              />
            )}
          </NativeChatWorkerApprovalTimeline>
        </NativeChatHostSetupContext.Provider>
      </NativeChatUsageLimitActionsProvider>
    </NativeChatRowActionsProvider>
  )
}
