// Where the folded chip sits over each card the dock can stack above the message box: centered,
// 8px above it, at every width and theme. Imported by run.mjs.
import { chip, toggle } from './fixture-session.mjs'

export async function runLayerPlacementChecks({ check, scene, assert, shot }) {
  for (const width of [720, 390, 320]) {
    for (const theme of ['light', 'dark']) {
      for (const layer of ['question', 'queue', 'both']) {
        await check(`sits centered just above the ${layer} (${width}px, ${theme})`, () =>
          scene(`${layer}${width}`, { width: width + 40, height: 900, theme }, async (page) => {
            const sibling =
              layer === 'queue'
                ? page.locator('[data-native-chat-queue] .rounded-lg').first()
                : page.locator('[data-native-chat-question-card] [data-native-chat-dock-clip]')
            const [a, b] = await Promise.all([chip(page).boundingBox(), sibling.boundingBox()])
            assert(a && b, 'chip or next card missing')
            const gap = b.y - a.y - a.height
            assert(Math.abs(gap - 8) <= 1, `gap is ${gap}px`)
            const offset = a.x + a.width / 2 - (b.x + b.width / 2)
            assert(Math.abs(offset) <= 1, `chip is ${offset}px off the next card's center`)
            assert(
              (await page.getByRole('button', { name: /Clear all/ }).count()) === 0,
              'folded Clear all is visible'
            )
            await shot(page, `${layer}-${width}-${theme}`)
            await toggle(page).click()
            await page.getByRole('button', { name: /Clear all/ }).waitFor()
          })
        )
      }
    }
  }
}
