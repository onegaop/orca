import type { ReactNode } from 'react'
import { Circle, ClipPath, Defs, G, Image, Path } from 'react-native-svg'
import { evaluateAvatarAnimationTrack } from '../../../src/shared/bots/avatar-packs/avatar-pack-track'
import type {
  AvatarKeyframedNode,
  AvatarPackAnimationResponse
} from '../../../src/shared/bots/avatar-packs/avatar-pack-types'

const MAX_NATIVE_NODES = 128
const NATIVE_TAGS = new Set(['defs', 'clipPath', 'circle', 'g', 'image', 'path'])
const NATIVE_TRACKS = new Set(['transform', 'opacity', 'path', 'present'])

type NativeAvatarNode = {
  node: AvatarKeyframedNode
  texture?: { uri: string }
  children: NativeAvatarNode[]
}

export function prepareNativeAvatarScene({ animation, textures }: AvatarPackAnimationResponse) {
  const [x, y, width, height] = animation.vb
  if (
    ![x, y, width, height].every(Number.isFinite) ||
    width <= 0 ||
    height <= 0 ||
    animation.nodes.length > MAX_NATIVE_NODES
  ) {
    return null
  }
  const root = animation.nodes.find((node) => node.tag === 'svg' && node.parent === null)
  if (!root) {
    return null
  }
  const children = new Map<string, NativeAvatarNode[]>()
  for (const node of animation.nodes) {
    if (node === root) {
      continue
    }
    if (
      !node.parent ||
      !NATIVE_TAGS.has(node.tag) ||
      Object.keys(node.tracks ?? {}).some((track) => !NATIVE_TRACKS.has(track))
    ) {
      return null
    }
    let texture: NativeAvatarNode['texture']
    if (node.tag === 'image') {
      const path = node.attrs?.['xlink:href'] ?? node.attrs?.href
      const uri = path ? textures[path] : undefined
      if (!uri) {
        return null
      }
      texture = { uri }
    }
    const siblings = children.get(node.parent) ?? []
    siblings.push({ node, texture, children: [] })
    children.set(node.parent, siblings)
  }

  const nodes = children.get(root.id) ?? []
  const reachable = [...nodes]
  for (const entry of reachable) {
    entry.children = children.get(entry.node.id) ?? []
    reachable.push(...entry.children)
  }
  return reachable.length === animation.nodes.length - 1 && nodes.length > 0
    ? { animation, nodes }
    : null
}

export function renderNativeAvatarNode(
  { node, texture, children }: NativeAvatarNode,
  progress: number
): ReactNode {
  const { id, tag, attrs = {}, tracks = {} } = node
  const present = tracks.present && evaluateAvatarAnimationTrack(tracks.present, progress)
  if (present != null && present !== 1 && present !== '1') {
    return null
  }
  const matrix = tracks.transform && evaluateAvatarAnimationTrack(tracks.transform, progress)
  const opacity = tracks.opacity && evaluateAvatarAnimationTrack(tracks.opacity, progress)
  const common = {
    id: attrs.id,
    opacity: (Array.isArray(opacity) ? opacity[0] : opacity) ?? attrs.opacity,
    transform:
      Array.isArray(matrix) && matrix.length === 6 && matrix.every(Number.isFinite)
        ? `matrix(${matrix.join(' ')})`
        : attrs.transform,
    clipPath: attrs['clip-path']
  }
  const paint = {
    fill: attrs.fill,
    fillOpacity: attrs['fill-opacity'],
    stroke: attrs.stroke,
    strokeWidth: attrs['stroke-width'],
    strokeOpacity: attrs['stroke-opacity']
  }
  const renderChildren = () => children.map((child) => renderNativeAvatarNode(child, progress))

  switch (tag) {
    case 'defs':
      return <Defs key={id}>{renderChildren()}</Defs>
    case 'clipPath':
      return (
        <ClipPath key={id} id={attrs.id}>
          {renderChildren()}
        </ClipPath>
      )
    case 'g':
      return (
        <G key={id} {...common} {...paint}>
          {renderChildren()}
        </G>
      )
    case 'circle':
      return <Circle key={id} {...common} {...paint} cx={attrs.cx} cy={attrs.cy} r={attrs.r} />
    case 'image':
      return (
        <Image
          key={id}
          {...common}
          href={texture}
          x={attrs.x}
          y={attrs.y}
          width={attrs.width}
          height={attrs.height}
          preserveAspectRatio={attrs.preserveAspectRatio}
        />
      )
    case 'path': {
      const path = tracks.path && evaluateAvatarAnimationTrack(tracks.path, progress)
      const end = attrs['stroke-linecap']
      const join = attrs['stroke-linejoin']
      return (
        <Path
          key={id}
          {...common}
          {...paint}
          d={path == null ? attrs.d : String(path)}
          strokeLinecap={end === 'round' || end === 'square' ? end : 'butt'}
          strokeLinejoin={join === 'round' || join === 'bevel' ? join : 'miter'}
        />
      )
    }
    default:
      return null
  }
}
