import { describe, expect, it } from 'vitest'
import { linkNativeChatFilePaths } from '../../../../../shared/native-chat/file-access/native-chat-file-link-tree'
import { routeNativeChatHref } from '../../../../../shared/native-chat/file-access/native-chat-href-routing'
import { remarkNativeChatFileDestinations } from './native-chat-markdown-file-destinations'

type Node = Parameters<ReturnType<typeof remarkNativeChatFileDestinations>>[0]

describe('native chat artifact destinations', () => {
  it('keeps a sandbox download in the click-only file route, preserving the literal path', () => {
    const url = 'sandbox:/Users/test/output/weekly%20report%3Ffinal.md'
    const link: Node = { type: 'link', url }
    const image: Node = { type: 'image', url: 'sandbox:/Users/test/output/chart.png' }
    const root: Node = { type: 'root', children: [{ type: 'paragraph', children: [link, image] }] }
    let probes = 0
    linkNativeChatFilePaths(root, () => {
      probes++
      return false
    })
    remarkNativeChatFileDestinations()(root)
    expect(routeNativeChatHref(link.url)).toEqual({
      kind: 'file',
      pathText: '/Users/test/output/weekly report?final.md',
      line: null,
      pathKind: 'literal'
    })
    expect(routeNativeChatHref(image.url)).toEqual({ kind: 'none' })
    expect(root.children).toHaveLength(1)
    expect(probes).toBe(0)
  })

  it('does not turn ambiguous or non-local sandbox URLs into file links', () => {
    const urls = [
      'sandbox://another-host/output/report.md',
      'sandbox:/output/%2e%2e/report.md',
      'sandbox:/output/smuggled%2fpath.md',
      'sandbox:/output/control%00.md',
      'sandbox:relative/report.md',
      'sandbox:/output/report.md?download=true'
    ]
    const links = urls.map((url) => ({ type: 'link', url }))
    remarkNativeChatFileDestinations()({ type: 'root', children: links })
    expect(links.map(({ url }) => routeNativeChatHref(url))).toEqual(
      urls.map(() => ({ kind: 'none' }))
    )
  })

  it('promotes only a single plain code-fenced file confirmed by the conversation host', () => {
    const path = '/Users/test/projects/nbp-market-app-my-optional-list-usage.md'
    const root = {
      type: 'root',
      children: [
        { type: 'code', lang: 'text', value: path },
        { type: 'code', lang: 'text', value: '/Users/test/projects/missing.md' },
        { type: 'code', lang: 'sh', value: path },
        { type: 'code', lang: 'text', value: `${path}\n${path}` }
      ]
    }
    linkNativeChatFilePaths(root, (link) => link.pathText === path)
    expect(root.children.map(({ type }) => type)).toEqual(['paragraph', 'code', 'code', 'code'])
  })
})
