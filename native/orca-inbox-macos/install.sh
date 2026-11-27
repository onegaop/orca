#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-27.2.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-27.2.0.app/Contents/Developer
fi
swift build --disable-sandbox -c release --product OrcaInbox
app="$HOME/Applications/Orca Inbox.app"
mkdir -p "$HOME/Applications"
stage=$(mktemp -d "$HOME/Applications/.orca-inbox-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Orca Inbox.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
install -m 755 .build/release/OrcaInbox "$bundle/Contents/MacOS/OrcaInbox"
install -m 644 ../../resources/build/icon.icns "$bundle/Contents/Resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.onegaop.orca-inbox</string>
<key>CFBundleExecutable</key><string>OrcaInbox</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Orca Inbox</string>
<key>CFBundleDisplayName</key><string>Orca 任务收件箱</string>
<key>CFBundleShortVersionString</key><string>0.4.2</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$bundle"
/usr/bin/codesign --verify --strict "$bundle"
if [[ -d "$app" ]]; then
    /usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" | /usr/bin/grep -qx 'com.onegaop.orca-inbox'
    # Replace only files belonging to this companion, never Orca.app.
    /usr/bin/ditto "$bundle" "$app"
else
    mv "$bundle" "$app"
fi
/usr/bin/codesign --verify --strict "$app"
echo "$app"
