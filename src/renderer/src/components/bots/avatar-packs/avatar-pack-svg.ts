import type { AvatarKeyframedAnimation, AvatarKeyframedNode } from './avatar-pack-types'

const SVG_TAGS = new Set([
  'svg',
  'g',
  'defs',
  'path',
  'rect',
  'circle',
  'ellipse',
  'line',
  'polyline',
  'polygon',
  'image',
  'use',
  'clipPath',
  'mask',
  'linearGradient',
  'radialGradient',
  'stop',
  'filter',
  'feBlend',
  'feColorMatrix',
  'feComponentTransfer',
  'feComposite',
  'feConvolveMatrix',
  'feDiffuseLighting',
  'feDisplacementMap',
  'feDistantLight',
  'feDropShadow',
  'feFlood',
  'feFuncA',
  'feFuncB',
  'feFuncG',
  'feFuncR',
  'feGaussianBlur',
  'feMerge',
  'feMergeNode',
  'feMorphology',
  'feOffset',
  'fePointLight',
  'feSpecularLighting',
  'feSpotLight',
  'feTile',
  'feTurbulence'
])
const SVG_ATTRIBUTES = new Set([
  'id',
  'viewBox',
  'preserveAspectRatio',
  'x',
  'y',
  'x1',
  'x2',
  'y1',
  'y2',
  'width',
  'height',
  'cx',
  'cy',
  'r',
  'rx',
  'ry',
  'd',
  'points',
  'transform',
  'opacity',
  'fill',
  'fill-opacity',
  'fill-rule',
  'stroke',
  'stroke-opacity',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'stroke-dasharray',
  'stroke-dashoffset',
  'clip-path',
  'clip-rule',
  'clipPathUnits',
  'mask',
  'maskUnits',
  'maskContentUnits',
  'filter',
  'filterUnits',
  'primitiveUnits',
  'color-interpolation-filters',
  'offset',
  'stop-color',
  'stop-opacity',
  'gradientUnits',
  'gradientTransform',
  'spreadMethod',
  'fx',
  'fy',
  'fr',
  'in',
  'in2',
  'result',
  'type',
  'values',
  'slope',
  'intercept',
  'amplitude',
  'exponent',
  'tableValues',
  'operator',
  'k1',
  'k2',
  'k3',
  'k4',
  'mode',
  'stdDeviation',
  'dx',
  'dy',
  'flood-color',
  'flood-opacity',
  'color',
  'scale',
  'xChannelSelector',
  'yChannelSelector',
  'radius',
  'baseFrequency',
  'numOctaves',
  'seed',
  'stitchTiles',
  'surfaceScale',
  'diffuseConstant',
  'specularConstant',
  'specularExponent',
  'lighting-color',
  'azimuth',
  'elevation',
  'z',
  'pointsAtX',
  'pointsAtY',
  'pointsAtZ',
  'limitingConeAngle',
  'order',
  'kernelMatrix',
  'divisor',
  'bias',
  'targetX',
  'targetY',
  'edgeMode',
  'kernelUnitLength',
  'preserveAlpha'
])
const SAFE_ID = /^[A-Za-z0-9_-]+$/
const SAFE_TEXTURE_PATH = /^[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\.(?:png|webp)$/i

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function safeAttribute(tag: string, key: string, value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 1_000_000) {
    return false
  }
  if (key === 'href' || key === 'xlink:href') {
    return tag === 'image' ? SAFE_TEXTURE_PATH.test(value) : /^#[A-Za-z0-9_-]+$/.test(value)
  }
  if (!SVG_ATTRIBUTES.has(key)) {
    return false
  }
  if (key === 'id') {
    return SAFE_ID.test(value)
  }
  // SVG paint and reference attributes may resolve only local definitions, never URLs or CSS escapes.
  if (/[\\<>]/.test(value) || Array.from(value).some((char) => char.charCodeAt(0) < 32)) {
    return false
  }
  return !/url\s*\(/i.test(value) || /^url\(#[A-Za-z0-9_-]+\)$/.test(value)
}

function safeTracks(value: unknown): AvatarKeyframedNode['tracks'] {
  if (!isRecord(value)) {
    return undefined
  }
  const tracks: NonNullable<AvatarKeyframedNode['tracks']> = {}
  for (const [key, track] of Object.entries(value)) {
    if (!['transform', 'opacity', 'path', 'present', 'slope', 'values'].includes(key)) {
      continue
    }
    if (!isRecord(track) || !Array.isArray(track.times) || !Array.isArray(track.values)) {
      continue
    }
    const { times, values } = track
    if (times.length === 0 || times.length > 10_000 || times.length !== values.length) {
      continue
    }
    if (
      !times.every(
        (time, i) =>
          typeof time === 'number' && Number.isFinite(time) && (i === 0 || time > times[i - 1])
      )
    ) {
      continue
    }
    if (
      !values.every((item) =>
        typeof item === 'number'
          ? Number.isFinite(item)
          : typeof item === 'string'
            ? item.length <= 1_000_000
            : Array.isArray(item) &&
              item.length <= 64 &&
              item.every((n) => typeof n === 'number' && Number.isFinite(n))
      )
    ) {
      continue
    }
    tracks[key] = { times, values, discrete: track.discrete === true }
  }
  return tracks
}

export function sanitizeAvatarPackAnimation(value: unknown): AvatarKeyframedAnimation | null {
  if (!isRecord(value) || !Array.isArray(value.nodes) || value.nodes.length > 10_000) {
    return null
  }
  const ids = new Set<string>()
  const nodes: AvatarKeyframedNode[] = []
  for (const node of value.nodes) {
    if (
      !isRecord(node) ||
      typeof node.id !== 'string' ||
      !SAFE_ID.test(node.id) ||
      ids.has(node.id) ||
      typeof node.tag !== 'string' ||
      !SVG_TAGS.has(node.tag)
    ) {
      continue
    }
    ids.add(node.id)
    const attrs: Record<string, string> = {}
    if (isRecord(node.attrs)) {
      for (const [key, attr] of Object.entries(node.attrs)) {
        if (safeAttribute(node.tag, key, attr)) {
          attrs[key] = attr
        }
      }
    }
    nodes.push({
      id: node.id,
      tag: node.tag,
      parent: typeof node.parent === 'string' ? node.parent : null,
      slot: 0,
      attrs,
      tracks: safeTracks(node.tracks)
    })
  }
  if (!nodes.some((node) => node.tag === 'svg')) {
    return null
  }
  const vb =
    Array.isArray(value.vb) &&
    value.vb.length === 4 &&
    value.vb.every((n) => typeof n === 'number' && Number.isFinite(n))
      ? value.vb
      : [0, 0, 100, 100]
  return {
    version: 1,
    pack: '',
    index: 0,
    state: '',
    variant: 0,
    name: '',
    nodes,
    duration:
      typeof value.duration === 'number' && Number.isFinite(value.duration) && value.duration > 0
        ? value.duration
        : 1,
    once: value.once === true,
    vb: vb as [number, number, number, number]
  }
}
