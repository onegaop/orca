import { createHash } from 'node:crypto'
import { access, mkdir, readFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { runProcess } from '@orca/process-host'

const COMPANION_APP_NAME = 'Orca Inbox.app'
const COMPANION_EXECUTABLE = 'OrcaInbox'
const COMPANION_BUNDLE_ID = 'com.onegaop.orca-inbox'
// Darwin 25 corresponds to macOS 26, which Orca Inbox's SwiftUI target requires.
const MIN_DARWIN_MAJOR = 25

async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath)
    return true
  } catch {
    return false
  }
}

async function bundleFingerprint(appDir: string): Promise<string | null> {
  try {
    const [binary, plist] = await Promise.all([
      readFile(path.join(appDir, 'Contents', 'MacOS', COMPANION_EXECUTABLE)),
      readFile(path.join(appDir, 'Contents', 'Info.plist'))
    ])
    return createHash('sha256').update(binary).update(plist).digest('hex')
  } catch {
    return null
  }
}

async function hasExpectedBundleId(appDir: string): Promise<boolean> {
  try {
    const plist = await readFile(path.join(appDir, 'Contents', 'Info.plist'), 'utf8')
    return plist.includes(`<string>${COMPANION_BUNDLE_ID}</string>`)
  } catch {
    return false
  }
}

function isMacOs26OrNewer(release: string = os.release()): boolean {
  const major = Number.parseInt(release.split('.')[0] ?? '', 10)
  return Number.isFinite(major) && major >= MIN_DARWIN_MAJOR
}

export async function syncBundledOrcaInboxCompanion(options: {
  homeDir: string
  resourcesPath: string
  isPackaged: boolean
  platform?: NodeJS.Platform
  darwinRelease?: string
}): Promise<'skipped' | 'unchanged' | 'synced'> {
  if ((options.platform ?? process.platform) !== 'darwin' || !options.isPackaged) {
    return 'skipped'
  }
  if (!isMacOs26OrNewer(options.darwinRelease)) {
    return 'skipped'
  }
  const sourceApp = path.join(options.resourcesPath, COMPANION_APP_NAME)
  const sourceHash = await bundleFingerprint(sourceApp)
  if (!sourceHash) {
    return 'skipped'
  }

  const applicationsDir = path.join(options.homeDir, 'Applications')
  const targetApp = path.join(applicationsDir, COMPANION_APP_NAME)
  const targetExists = await pathExists(targetApp)
  if (targetExists) {
    // Refuse to overwrite an unrelated app at the same path.
    if (!(await hasExpectedBundleId(targetApp))) {
      return 'skipped'
    }
    const targetHash = await bundleFingerprint(targetApp)
    if (targetHash === sourceHash) {
      return 'unchanged'
    }
  }

  await mkdir(applicationsDir, { recursive: true })
  const wasRunning = await runProcess({
    program: '/usr/bin/pgrep',
    args: ['-x', COMPANION_EXECUTABLE],
    stdio: 'ignore',
    timeoutMs: 2_000
  }).then(
    (result) => result.code === 0,
    () => false
  )

  if (wasRunning) {
    await runProcess({
      program: '/usr/bin/pkill',
      args: ['-x', COMPANION_EXECUTABLE],
      stdio: 'ignore',
      timeoutMs: 2_000
    }).catch(() => {})
  }

  // ditto preserves nested macOS code signatures and extended attributes atomically into place.
  const copyResult = await runProcess({
    program: '/usr/bin/ditto',
    args: [sourceApp, targetApp],
    stdio: 'ignore',
    timeoutMs: 15_000
  })
  if (copyResult.code !== 0) {
    throw new Error(
      `ditto failed syncing ${COMPANION_APP_NAME} (exit ${copyResult.code ?? 'null'})`
    )
  }

  if (wasRunning) {
    // Relaunch in the background so updating the companion never steals focus from Orca.
    await runProcess({
      program: '/usr/bin/open',
      args: ['-g', '-a', targetApp],
      stdio: 'ignore',
      timeoutMs: 5_000
    }).catch(() => {})
  }

  return 'synced'
}
