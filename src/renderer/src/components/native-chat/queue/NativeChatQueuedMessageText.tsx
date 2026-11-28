import {
  NATIVE_CHAT_UNKERNED_CSS,
  nativeChatTextHasUnkernedRun
} from '@/components/native-chat/composer/editor/native-chat-unkerned-runs'
import {
  NativeChatReplyQuoteChip,
  NativeChatReplyQuoteFull,
  type NativeChatReplyQuote
} from '../composer/reply/NativeChatReplyQuoteChip'

export function QueuedMessageText({
  expandedId,
  text,
  quote,
  measureLine,
  measureQuote
}: {
  expandedId?: string
  text: string
  quote: NativeChatReplyQuote | null
  measureLine: (line: HTMLElement | null) => void
  measureQuote: (line: HTMLElement | null) => void
}): React.JSX.Element {
  if (expandedId === undefined) {
    return (
      <>
        {text ? (
          <p ref={measureLine} className="truncate text-sm text-foreground" title={text}>
            {text}
          </p>
        ) : null}
        {quote ? (
          <NativeChatReplyQuoteChip quote={quote} className="mb-0" measureExcerpt={measureQuote} />
        ) : null}
      </>
    )
  }
  return (
    <div id={expandedId} className="scrollbar-sleek mt-1 max-h-60 overflow-y-auto">
      {text ? (
        <p
          className="whitespace-pre-wrap break-words text-sm text-foreground"
          style={nativeChatTextHasUnkernedRun(text) ? NATIVE_CHAT_UNKERNED_CSS : undefined}
        >
          {text}
        </p>
      ) : null}
      {quote ? <NativeChatReplyQuoteFull quote={quote} /> : null}
    </div>
  )
}
