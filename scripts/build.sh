#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app_dir="$PWD/.build/File Cleanup.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/ScreenshotCleanup "$app_dir/Contents/MacOS/ScreenshotCleanup"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
