import { DiffHunksRenderer, parseDiffFromFile, type ThemedDiffResult } from '@pierre/diffs'
import { TextDocument } from '@pierre/diffs/edit'
import type { WorkerPoolManager } from '@pierre/diffs/worker'
import { expect, it, vi } from 'vitest'

it('starts editing from a worker result without mutating its source rows', () => {
  const options = { theme: 'dark-plus', useTokenTransformer: true }
  const external = {
    ...parseDiffFromFile(null, { name: 'file.ts', contents: 'new\n' }),
    cacheKey: 'external'
  }
  const highlighted = {
    type: 'element' as const,
    tagName: 'div',
    properties: {},
    children: [
      {
        type: 'element' as const,
        tagName: 'span',
        properties: { 'data-char': 0 },
        children: [{ type: 'text' as const, value: 'new' }]
      }
    ]
  }
  const result: ThemedDiffResult = {
    code: { additionLines: [highlighted], deletionLines: [] },
    themeStyles: '',
    baseThemeType: undefined
  }
  const decode = vi.fn(() => highlighted)
  Object.defineProperty(result.code.additionLines, 0, { get: decode })
  // oxlint-disable-next-line typescript/consistent-type-assertions -- SAFETY: The renderer uses only these worker fields to read the primed cache.
  const worker = {
    isWorkingPool: () => true,
    shouldHighlightOnMainThread: () => false,
    cancelLocalThemeRender: () => {},
    getDiffRenderOptions: () => options,
    getDiffResultCache: () => ({ options, result })
  } as unknown as WorkerPoolManager
  const renderer = new DiffHunksRenderer({ disableFileHeader: true }, undefined, undefined, worker)
  renderer.renderDiff(external)
  decode.mockClear()
  const session = renderer.startEditSession(external)
  expect(renderer.editorRenderReady()).toBe(true)
  expect(decode).not.toHaveBeenCalled()
  expect(renderer.diffCache).toBe(session)
  const document = new TextDocument('file.ts', 'new\n', 'typescript')
  const change = document.applyEdits([
    {
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
      newText: 'edited'
    }
  ])!
  renderer.applyChange(change, document, new Map([[0, [[0, '#ffffff', 'edited']]]]))
  expect(decode).not.toHaveBeenCalled()
  expect(session.additionLines).toEqual(['edited\n'])
  expect(external.additionLines).toEqual(['new\n'])
  expect(result.code.additionLines[0]).toBe(highlighted)
})

it('does not adopt a worker result without the editor token transformer', () => {
  const external = {
    ...parseDiffFromFile(null, { name: 'file.ts', contents: 'new\n' }),
    cacheKey: 'external'
  }
  // oxlint-disable-next-line typescript/consistent-type-assertions -- SAFETY: The cache-adoption seam uses only these worker/result fields; no highlighting or DOM render runs.
  const worker = {
    isWorkingPool: () => true,
    getDiffRenderOptions: () => ({ theme: 'dark-plus', useTokenTransformer: true }),
    getDiffResultCache: () => ({
      options: { theme: 'dark-plus', useTokenTransformer: false },
      result: {}
    })
  } as unknown as WorkerPoolManager
  const renderer = new DiffHunksRenderer({}, undefined, undefined, worker)
  renderer.startEditSession(external)
  expect(renderer.editorRenderReady()).toBe(false)
})

it('updates whitespace-ignoring replacement hunks incrementally until an edit matches the original', () => {
  const options = { theme: 'dark-plus', useTokenTransformer: true }
  const original = 'const original = 1\nconst second = 2\n'
  const modified = 'const changed = 3\nconst current = 4\n'
  const external = {
    ...parseDiffFromFile(
      { name: 'file.ts', contents: original },
      { name: 'file.ts', contents: modified },
      { ignoreWhitespace: true }
    ),
    cacheKey: 'external'
  }
  const result: ThemedDiffResult = {
    code: { additionLines: [], deletionLines: [] },
    themeStyles: '',
    baseThemeType: undefined
  }
  // oxlint-disable-next-line typescript/consistent-type-assertions -- SAFETY: Only cache reads run; no worker is dispatched by this edit-session test.
  const worker = {
    isWorkingPool: () => true,
    getDiffRenderOptions: () => options,
    getDiffResultCache: () => ({ options, result })
  } as unknown as WorkerPoolManager
  const renderer = new DiffHunksRenderer(
    { parseDiffOptions: { ignoreWhitespace: true } },
    undefined,
    undefined,
    worker
  )
  const session = renderer.startEditSession(external)
  const hunks = session.hunks
  const document = new TextDocument('file.ts', modified, 'typescript')
  const edit = (newText: string) => {
    const change = document.applyEdits([
      {
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: document.getLineLength(1) }
        },
        newText
      }
    ])!
    renderer.applyChange(change, document)
  }
  edit('const current = 45')
  expect(session.hunks).toBe(hunks)
  expect(session.additionLines[1]).toBe('const current = 45\n')
  edit('  const second = 2  ')
  expect(session.hunks).not.toBe(hunks)
  expect(session.hunks.flatMap((hunk) => hunk.hunkContent)).toContainEqual(
    expect.objectContaining({ type: 'context', lines: 1 })
  )
  expect(external.additionLines.join('')).toBe(modified)
})
