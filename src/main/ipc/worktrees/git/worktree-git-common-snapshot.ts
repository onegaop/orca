import { readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { forEachWithConcurrency } from '../../../../shared/concurrency/map-with-concurrency'
import { PRIMARY_CHECKOUT_METADATA_FILES } from './worktree-git-common-metadata-files'
import {
  gitCommonDirectoryIdentity,
  type GitCommonSnapshot
} from './worktree-git-common-snapshot-diff'
import {
  gitCommonDirectorySignature,
  gitCommonFileSignature,
  isGitCommonEntrySettled,
  snapshotGitCommonEntry,
  type GitCommonEntrySnapshot
} from './worktree-git-common-entry-snapshot'

// Match existing probe pools to bound fleet stat fanout without flooding libuv (#17828).
const GIT_COMMON_SNAPSHOT_CONCURRENCY = 8

async function snapshotStatusRefSignatures(
  paths: ReadonlySet<string>
): Promise<Map<string, string>> {
  const signatures = new Map<string, string>()
  await forEachWithConcurrency([...paths], GIT_COMMON_SNAPSHOT_CONCURRENCY, async (path) => {
    const signature = await gitCommonFileSignature(path)
    if (signature !== null) {
      signatures.set(path, signature)
    }
  })
  return signatures
}

async function snapshotPrimaryCheckoutSignatures(
  commonDirPath: string
): Promise<Map<string, string>> {
  const signatures = new Map<string, string>()
  await Promise.all(
    PRIMARY_CHECKOUT_METADATA_FILES.map(async (name) => {
      const signature = await gitCommonFileSignature(join(commonDirPath, name))
      if (signature !== null) {
        signatures.set(name, signature)
      }
    })
  )
  return signatures
}

type GitCommonSnapshotOptions = {
  previous?: GitCommonSnapshot
  includePrimary: boolean
  forceFullScan?: boolean
  statusRefPaths: Set<string>
  statInPlaceLeaves?: boolean
  onDirGateMiss?: () => void
  onRootMissing?: () => void
  fallbackRegistration?: { quietTicksByPath: Map<string, number>; maxQuietTicks: number }
}

export async function snapshotGitCommon(
  commonDirPath: string,
  {
    previous,
    includePrimary,
    forceFullScan = false,
    statusRefPaths,
    statInPlaceLeaves,
    onDirGateMiss,
    onRootMissing,
    fallbackRegistration
  }: GitCommonSnapshotOptions
): Promise<GitCommonSnapshot> {
  const worktreesDir = join(commonDirPath, 'worktrees')
  const [worktreesDirSignature, primarySignatures, statusRefSignatures] = await Promise.all([
    gitCommonDirectorySignature(worktreesDir, previous?.worktreesDirSignature, onRootMissing),
    includePrimary ? snapshotPrimaryCheckoutSignatures(commonDirPath) : new Map<string, string>(),
    snapshotStatusRefSignatures(statusRefPaths)
  ])
  const worktreesDirIdentity = gitCommonDirectoryIdentity(worktreesDirSignature)
  // List every tick: coarse directory signatures can miss add/remove changes before the slow backstop.
  let entryPaths: string[]
  let retainedPreviousListing = false
  try {
    const entries = await readdir(worktreesDir, { withFileTypes: true })
    entryPaths = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(worktreesDir, entry.name))
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      entryPaths = []
    } else {
      // Transient readdir failures are not deletion proof; keep entries until a later listing drops them.
      retainedPreviousListing = true
      entryPaths = previous ? [...previous.entries.keys()] : []
    }
  }

  const reuseKnownEntries =
    fallbackRegistration !== undefined &&
    !forceFullScan &&
    !retainedPreviousListing &&
    previous?.worktreesDirIdentity === worktreesDirIdentity
  const quietTicksByPath = fallbackRegistration?.quietTicksByPath
  const entries = new Map<string, GitCommonEntrySnapshot>()
  await forEachWithConcurrency(entryPaths, GIT_COMMON_SNAPSHOT_CONCURRENCY, async (entryPath) => {
    const previousEntry = previous?.entries.get(entryPath)
    const quietTicks = quietTicksByPath?.get(entryPath) ?? 0
    if (
      reuseKnownEntries &&
      previousEntry &&
      (isGitCommonEntrySettled(previousEntry) || quietTicks >= fallbackRegistration.maxQuietTicks)
    ) {
      entries.set(entryPath, previousEntry)
      return
    }
    const entry = await snapshotGitCommonEntry(
      entryPath,
      previousEntry,
      forceFullScan,
      statInPlaceLeaves,
      onDirGateMiss
    )
    if (quietTicksByPath) {
      if (isGitCommonEntrySettled(entry)) {
        quietTicksByPath.delete(entryPath)
      } else {
        // A locked or no-checkout worktree can stay unsettled after registration finishes.
        const quiet = entry.dirSignature === previousEntry?.dirSignature
        quietTicksByPath.set(entryPath, quiet ? quietTicks + 1 : 0)
      }
    }
    entries.set(entryPath, entry)
  })
  if (quietTicksByPath) {
    for (const entryPath of quietTicksByPath.keys()) {
      if (!entries.has(entryPath)) {
        quietTicksByPath.delete(entryPath)
      }
    }
  }
  // Full-scan metrics count ungated metadata sweeps, not the cheap per-tick directory listing.
  return {
    worktreesDirSignature,
    worktreesDirIdentity,
    entries,
    primarySignatures,
    statusRefPaths,
    statusRefSignatures,
    didFullScan: forceFullScan
  }
}
