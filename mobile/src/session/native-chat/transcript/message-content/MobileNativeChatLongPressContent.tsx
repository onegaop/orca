import type { ComponentProps, ReactNode } from 'react'
import { Pressable, View } from 'react-native'
import {
  isImageRefBlock,
  type NativeChatMessage
} from '../../../../../../src/shared/native-chat/native-chat-types'
import { useThemedStyles } from '../../../../theme/themed-styles'
import { useNativeChatMarkdownImageSize } from '../../preferences/native-chat-markdown-image-size'
import { stylesSheet } from '../messages/mobile-native-chat-message-styles'
import { mobileNativeChatMarkdownImageSources } from './mobile-native-chat-markdown-image-sources'

// Android uses a message-actions long press; other platforms keep native inline selection.
export function MobileNativeChatLongPressContent({
  onLongPress,
  style,
  userMessage,
  children
}: {
  onLongPress?: () => void
  style?: ComponentProps<typeof View>['style']
  userMessage?: NativeChatMessage
  children: ReactNode
}): React.JSX.Element {
  const styles = useThemedStyles(stylesSheet)
  const imageSize = useNativeChatMarkdownImageSize()
  const columnImage =
    userMessage &&
    imageSize === 'column' &&
    (userMessage.blocks.some(isImageRefBlock) ||
      mobileNativeChatMarkdownImageSources(userMessage).length > 0)
  const contentStyle = [
    style ?? styles.content,
    userMessage && styles.userBubble,
    columnImage && styles.userBubbleColumnWidth
  ]
  return onLongPress ? (
    // Not one accessible element: screen readers keep reaching the text and controls inside.
    <Pressable onLongPress={onLongPress} accessible={false} style={contentStyle}>
      {children}
    </Pressable>
  ) : (
    <View style={contentStyle}>{children}</View>
  )
}
