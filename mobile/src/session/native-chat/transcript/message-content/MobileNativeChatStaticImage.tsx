import { Image, type ImageStyle, type StyleProp } from 'react-native'

export type MobileNativeChatInlineImageProps = {
  uri: string
  style: StyleProp<ImageStyle>
  onLoad: (width: number, height: number) => void
}

export function MobileNativeChatStaticImage({
  uri,
  style,
  onLoad
}: MobileNativeChatInlineImageProps) {
  return (
    <Image
      source={{ uri }}
      style={style}
      resizeMode="contain"
      onLoad={({ nativeEvent: { source } }) => onLoad(source.width, source.height)}
    />
  )
}
