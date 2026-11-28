import { useNativeChatCompactContext } from './use-native-chat-compact-context'
import { useNativeChatContextUsageSummary } from './use-native-chat-context-usage-summary'

export function useNativeChatComposerUsage(
  structuredTransport: Parameters<typeof useNativeChatContextUsageSummary>[0]
) {
  return {
    contextUsage: useNativeChatContextUsageSummary(structuredTransport),
    onCompactContext: useNativeChatCompactContext(structuredTransport)
  }
}
