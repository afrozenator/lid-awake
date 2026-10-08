#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$HOME/Applications/Lid Awake.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
/usr/bin/xcrun swiftc -O -framework AppKit "$source_dir/main.swift" -o "$app_dir/Contents/MacOS/LidAwake"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Lid Awake</string>
  <key>CFBundleDisplayName</key><string>Lid Awake</string>
  <key>CFBundleIdentifier</key><string>local.afro.lidawake</string>
  <key>CFBundleExecutable</key><string>LidAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
"$app_dir/Contents/MacOS/LidAwake" --self-test
"$app_dir/Contents/MacOS/LidAwake" --status
printf 'Installed: %s\n' "$app_dir"
