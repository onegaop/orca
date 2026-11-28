const { join, resolve } = require('node:path')

const root = resolve(__dirname, '../../../..')
const base = require(join(root, 'config/electron-builder.config.cjs'))
const hasSigningIdentity = Boolean(process.env.CSC_NAME)

module.exports = {
  ...base,
  directories: {
    ...base.directories,
    output: process.env.ORCA_PACKAGE_OUTPUT_DIR || join(root, 'dist/fork-arm64')
  },
  files: [
    ...base.files,
    '!{dist,test-results,.cache,.tmp,.anti-slop-plugin}{,/**/*}',
    '!.mcp.json'
  ],
  mac: {
    ...base.mac,
    target: ['dmg', 'zip'].map((target) => ({ target, arch: ['arm64'] })),
    ...(hasSigningIdentity
      ? { sign: join(root, 'config/scripts/desktop-distribution/macos/sign-mac-app.mjs') }
      : { identity: '-' })
  }
}
