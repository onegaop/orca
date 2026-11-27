#!/bin/bash
set -euo pipefail
test "$(uname -m)" = arm64
root="$(mktemp -d "$RUNNER_TEMP/orca-updater.XXXXXX")"
cd "$root"
umask 077
/usr/bin/sw_vers
npm init -y >/dev/null
npm install --save-exact --no-audit --no-fund electron@45.4.1
id='local.onegaop.orca.cloud-updater-smoke'
keychain="$root/smoke.keychain"
openssl="$(brew --prefix openssl@3)/bin/openssl"
pw="$("$openssl" rand -hex 24)"
echo "::add-mask::$pw"
security create-keychain -p "$pw" "$keychain"
cleanup() {
  if [[ -n "${server:-}" ]]; then kill "$server" 2>/dev/null || true; fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
}
trap cleanup EXIT
security unlock-keychain -p "$pw" "$keychain"
"$openssl" req -new -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Orca ephemeral Cloud Smoke" -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,digitalSignature,keyCertSign' -addext 'extendedKeyUsage=critical,codeSigning' -keyout smoke.key -out smoke.crt 2>/dev/null
"$openssl" pkcs12 -export -inkey smoke.key -in smoke.crt -out smoke.p12 -legacy -passout "pass:$pw"
security import smoke.p12 -f pkcs12 -k "$keychain" -P "$pw" -T /usr/bin/codesign >/dev/null
rm smoke.key smoke.p12
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" smoke.crt
security set-key-partition-list -S apple-tool:,apple: -s -k "$pw" "$keychain" >/dev/null
fingerprint="$("$openssl" x509 -in smoke.crt -outform DER | shasum | awk '{print $1}')"
requirement="identifier \"$id\" and certificate leaf = H\"$fingerprint\""
mkdir state
cat > main.cjs <<'JS'
const { app, autoUpdater } = require('electron')
const fs = require('node:fs')
const { root, version } = require('./fixture.json')
app.setPath('userData', root + '/state')
const report = (event, details='') => fs.appendFileSync(root+'/events', [version,event,details].join(' ')+'\n')
const timeout = setTimeout(() => { report('TIMEOUT'); app.exit(7) }, 90000)
app.whenReady().then(() => {
  const marker = app.getPath('userData')+'/workspace'
  if (version === '1.0.0' && !fs.existsSync(marker)) fs.writeFileSync(marker, 'existing-profile')
  report('LAUNCHED', fs.existsSync(marker) ? fs.readFileSync(marker,'utf8') : 'missing-profile')
  if (version !== '1.0.0') { clearTimeout(timeout); app.quit(); return }
  autoUpdater.on('error', err => { report('ERROR', err.message); app.exit(3) })
  autoUpdater.on('update-available', () => report('AVAILABLE'))
  autoUpdater.on('update-downloaded', () => { report('DOWNLOADED'); autoUpdater.quitAndInstall() })
  autoUpdater.setFeedURL({url: fs.readFileSync(root+'/feed', 'utf8').trim()})
  autoUpdater.checkForUpdates()
})
JS
for label in A B C; do
  case "$label" in A) version=1.0.0;; B) version=1.0.1;; C) version=1.0.2;; esac
  mkdir "$label"
  path="$root/$label/Orca Update Smoke.app"
  ditto node_modules/electron/dist/Electron.app "$path"
  p="$path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $id" -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $version" -c 'Add :LSUIElement bool true' "$p"
  dest="$path/Contents/Resources/app"
  mkdir "$dest"
  cp main.cjs "$dest/"
  printf '{"name":"orca-update-smoke","version":"%s","main":"main.cjs"}\n' "$version" > "$dest/package.json"
  printf '{"root":"%s","version":"%s"}\n' "$root" "$version" > "$dest/fixture.json"
  if [[ "$label" == C ]]; then
    codesign --force --deep --sign - "$path"
  else
    codesign --force --deep --sign "$fingerprint" --keychain "$keychain" --timestamp=none "$path"
    codesign --force --sign "$fingerprint" --keychain "$keychain" --timestamp=none --requirements "=designated => $requirement" "$path"
    codesign --verify --deep --strict -R="$requirement" "$path"
  fi
  if [[ "$label" != A ]]; then ditto -c -k --keepParent "$path" "$root/$label.zip"; fi
done
cat > server.cjs <<'JS'
const http=require('node:http'), fs=require('node:fs')
const server=http.createServer((req,res) => {
  const target=fs.readFileSync('target','utf8').trim()
  console.log(req.method, req.url, target)
  if (req.url==='/update') {
    res.setHeader('content-type','application/json')
    return res.end(JSON.stringify({url:'http://127.0.0.1:'+server.address().port+'/'+target+'.zip'}))
  }
  if (req.url==='/'+target+'.zip') {
    res.writeHead(200,{'Content-Type':'application/zip','Content-Length':fs.statSync(target+'.zip').size})
    return fs.createReadStream(target+'.zip').pipe(res)
  }
  res.writeHead(404).end()
})
server.listen(0,'127.0.0.1',()=>fs.writeFileSync('feed','http://127.0.0.1:'+server.address().port+'/update'))
JS
node server.cjs &
server=$!
for _ in {1..30}; do [[ -s feed ]] && break; sleep 1; done
test -s feed
exe="$root/A/Orca Update Smoke.app/Contents/MacOS/Electron"
plist="$root/A/Orca Update Smoke.app/Contents/Info.plist"
echo C > target
rc=0
"$exe" || rc=$?
cat events
test "$rc" = 3
grep -Eiq 'ERROR .*sign|ERROR .*requirement' events
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = 1.0.0
! grep -q DOWNLOADED events
echo B > target
"$exe"
for _ in {1..60}; do grep -q '^1.0.1 LAUNCHED existing-profile$' events && break; sleep 1; done
cat events
grep -q '^1.0.0 DOWNLOADED' events
grep -q '^1.0.1 LAUNCHED existing-profile$' events
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = 1.0.1
codesign --verify --deep --strict -R="$requirement" "$root/A/Orca Update Smoke.app"
