import { expect, it } from 'vitest'
import { parseInboxSessionLink } from './inbox-session-link'

const link =
  'orca://inbox/session?environment=mini&workspace=folder%3A%2Ftmp%2Fa%2Bb%26c&pane=tab%3A29e5521c-547a-44e3-8244-1346764d878a&id=1d43b664-1c98-4a0c-897e-8afed831db92&host=local'

it('preserves the exact workspace and pane the Inbox link addresses', () => {
  expect(parseInboxSessionLink(link)).toEqual({
    environmentId: 'mini',
    worktreeId: 'folder:/tmp/a+b&c',
    paneKey: 'tab:29e5521c-547a-44e3-8244-1346764d878a',
    sessionId: '1d43b664-1c98-4a0c-897e-8afed831db92',
    hostId: 'local'
  })
  expect(parseInboxSessionLink(`${link}&environment=local`)).toBeNull()
})
