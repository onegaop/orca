import { describe, expect, it } from 'vitest'
import { sanitizeAvatarPackAnimation } from './avatar-pack-svg'

describe('avatar pack SVG security boundary', () => {
  it('keeps inert drawing data while discarding active elements, events and nonlocal references', () => {
    const animation = sanitizeAvatarPackAnimation({
      duration: 2,
      vb: [0, 0, 100, 100],
      nodes: [
        { id: 'root', tag: 'svg', attrs: { viewBox: '0 0 100 100', onload: 'blocked' } },
        { id: 'clip', tag: 'clipPath', attrs: { id: 'clip' } },
        {
          id: 'body',
          tag: 'path',
          attrs: {
            d: 'M0 0L10 10',
            fill: 'url(#clip)',
            stroke: 'url(https://example.invalid/paint)',
            style: 'display: none',
            onclick: 'blocked'
          }
        },
        { id: 'texture', tag: 'image', attrs: { href: 'body.webp' } },
        { id: 'outside', tag: 'image', attrs: { href: '../outside.png' } },
        { id: 'vector', tag: 'image', attrs: { href: 'active.svg' } },
        { id: 'reference', tag: 'use', attrs: { href: '#body' } },
        { id: 'remote', tag: 'use', attrs: { href: 'https://example.invalid/image.svg' } },
        { id: 'active', tag: 'script' },
        { id: 'foreign', tag: 'foreignObject' },
        { id: 'navigation', tag: 'a', attrs: { href: '#body' } },
        { id: 'mutation', tag: 'set', attrs: { attributeName: 'href' } }
      ]
    })
    expect(animation?.nodes.map((node) => node.id)).toEqual([
      'root',
      'clip',
      'body',
      'texture',
      'outside',
      'vector',
      'reference',
      'remote'
    ])
    expect(animation?.nodes.map((node) => node.attrs)).toEqual([
      { viewBox: '0 0 100 100' },
      { id: 'clip' },
      { d: 'M0 0L10 10', fill: 'url(#clip)' },
      { href: 'body.webp' },
      {},
      {},
      { href: '#body' },
      {}
    ])
    expect(animation?.duration).toBe(2)
  })

  it('bounds malformed nodes and tracks before they reach SVG construction and frame interpolation', () => {
    const animation = sanitizeAvatarPackAnimation({
      duration: -1,
      nodes: [
        null,
        { id: 'root', tag: 'svg' },
        { id: 'root', tag: 'svg' },
        {
          id: 'body',
          tag: 'path',
          tracks: {
            opacity: { times: [0, 1], values: [0, 1] },
            transform: {
              times: [0, 0],
              values: [
                [1, 0],
                [0, 1]
              ]
            },
            path: { times: [0], values: [{}] },
            onclick: { times: [0], values: ['blocked'] }
          }
        }
      ]
    })
    expect(animation?.nodes.map((node) => node.id)).toEqual(['root', 'body'])
    expect(animation?.nodes[1]?.tracks).toEqual({
      opacity: { times: [0, 1], values: [0, 1], discrete: false }
    })
    expect(animation?.duration).toBe(1)
    expect(
      sanitizeAvatarPackAnimation({ nodes: [null, { tag: 'script', id: 'active' }] })
    ).toBeNull()
  })
})
