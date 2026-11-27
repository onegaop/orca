import type { UIZoomDirection, UIZoomRegion } from '../app-lifecycle/windows/ui-zoom-level'
import { keybindingMatchesAction } from './matching'
import type {
  KeybindingActionId,
  KeybindingInput,
  KeybindingMatchOptions,
  KeybindingOverrides
} from './types'

export type ZoomShortcutAction = { type: 'zoom'; direction: UIZoomDirection; region?: UIZoomRegion }

const ZOOM_ACTIONS: readonly ZoomShortcutAction[] = (['in', 'out', 'reset'] as const).flatMap(
  (direction): ZoomShortcutAction[] => [
    { type: 'zoom', direction },
    { type: 'zoom', region: 'sidebar', direction },
    { type: 'zoom', region: 'panel', direction }
  ]
)

export function zoomShortcutId({ region, direction }: ZoomShortcutAction): KeybindingActionId {
  return region ? `zoom.${region}.${direction}` : `zoom.${direction}`
}

export function resolveZoomShortcut(
  input: KeybindingInput,
  platform: NodeJS.Platform,
  keybindings?: KeybindingOverrides,
  options: KeybindingMatchOptions = {}
): ZoomShortcutAction | null {
  for (const action of ZOOM_ACTIONS) {
    if (keybindingMatchesAction(zoomShortcutId(action), input, platform, keybindings, options)) {
      return action
    }
  }
  return null
}
