import { Image } from 'expo-image'
import {
  MobileNativeChatStaticImage,
  type MobileNativeChatInlineImageProps
} from './MobileNativeChatStaticImage'

export function MobileNativeChatInlineImage({
  uri,
  style,
  onLoad
}: MobileNativeChatInlineImageProps) {
  if (!/^data:image\/webp[;,]/i.test(uri)) {
    return <MobileNativeChatStaticImage uri={uri} style={style} onLoad={onLoad} />
  }

  return (
    <Image
      source={{ uri }}
      style={style}
      contentFit="contain"
      useAppleWebpCodec={false}
      cachePolicy="none"
      onLoad={({ source }) => onLoad(source.width, source.height)}
    />
  )
}
