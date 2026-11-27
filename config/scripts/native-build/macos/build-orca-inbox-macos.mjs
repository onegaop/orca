import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const repoRoot = path.resolve(import.meta.dirname, '../../../..')
const packagePath = path.join(repoRoot, 'native', 'orca-inbox-macos')
const binaryPath = path.join(packagePath, '.build', 'release', 'OrcaInbox')
const appPath = path.join(packagePath, '.build', 'release', 'Orca Inbox.app')
const appExecutablePath = path.join(appPath, 'Contents', 'MacOS', 'OrcaInbox')
const appIconPath = path.join(appPath, 'Contents', 'Resources', 'AppIcon.icns')
const sourceIconPath = path.join(repoRoot, 'resources', 'build', 'icon.icns')
const signingIdentity = resolveSigningIdentity()

if (process.platform !== 'darwin') {
  process.exit(0)
}

buildBinary()
createCompanionApp()

function buildEnv() {
  if (
    !process.env.DEVELOPER_DIR &&
    existsSync('/Applications/Xcode-27.2.0.app/Contents/Developer')
  ) {
    return { ...process.env, DEVELOPER_DIR: '/Applications/Xcode-27.2.0.app/Contents/Developer' }
  }
  return process.env
}

function buildBinary() {
  run(
    'swift',
    [
      'build',
      '--disable-sandbox',
      '-c',
      'release',
      '--package-path',
      packagePath,
      '--product',
      'OrcaInbox'
    ],
    buildEnv()
  )
  chmodSync(binaryPath, 0o755)
}

function createCompanionApp() {
  rmSync(appPath, { recursive: true, force: true })
  mkdirSync(path.dirname(appExecutablePath), { recursive: true })
  mkdirSync(path.dirname(appIconPath), { recursive: true })
  copyFileSync(binaryPath, appExecutablePath)
  copyFileSync(sourceIconPath, appIconPath)
  chmodSync(appExecutablePath, 0o755)
  const plistPath = path.join(appPath, 'Contents', 'Info.plist')
  writeFileSync(plistPath, infoPlist(), 'utf8')
  run('/usr/bin/plutil', ['-lint', plistPath])
  run('/usr/bin/codesign', codesignArgs(signingIdentity, appPath))
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', appPath])
}

function codesignArgs(identity, targetPath) {
  const args = ['--force', '--deep', '--sign', identity]
  if (process.env.ORCA_MAC_RELEASE === '1' && identity !== '-') {
    args.push('--options', 'runtime', '--timestamp')
  }
  args.push(targetPath)
  return args
}

function resolveSigningIdentity() {
  const explicitIdentity = process.env.ORCA_COMPUTER_MACOS_SIGN_IDENTITY ?? process.env.CSC_NAME
  if (explicitIdentity) {
    return explicitIdentity
  }
  const identities = spawnSync('security', ['find-identity', '-v', '-p', 'codesigning'], {
    encoding: 'utf8'
  })
  if (identities.status !== 0 || !identities.stdout) {
    return '-'
  }
  const developmentMatch = identities.stdout.match(/"([^"]*Apple Development:[^"]+)"/)
  if (process.env.ORCA_MAC_RELEASE !== '1' && developmentMatch) {
    return developmentMatch[1]
  }
  const releaseMatch =
    identities.stdout.match(/"([^"]*Developer ID Application:[^"]+)"/) ??
    identities.stdout.match(/"([^"]*Apple Distribution:[^"]+)"/)
  return releaseMatch?.[1] ?? developmentMatch?.[1] ?? '-'
}

function run(command, args, env = process.env) {
  const result = spawnSync(command, args, { stdio: 'inherit', env })
  if (result.signal) {
    process.kill(process.pid, result.signal)
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
}

function infoPlist() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.onegaop.orca-inbox</string>
  <key>CFBundleExecutable</key>
  <string>OrcaInbox</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Orca Inbox</string>
  <key>CFBundleDisplayName</key>
  <string>Orca 任务收件箱</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>4</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
`
}
