#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PlansBar"
BUNDLE_ID="io.github.zergzorg.plansbar"
BUNDLE="build/${APP_NAME}.app"
ICON_SOURCE="Resources/AppIcon.png"
ICONSET="build/AppIcon.iconset"

echo "→ Building release binary"
swift build -c release

echo "→ Creating ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
strip -S "${BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "→ Creating app icon"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null
iconutil --convert icns "${ICONSET}" --output "${BUNDLE}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET}"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>PlansBar</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>PlansBar reads plan files from a workspace you choose.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>PlansBar reads plan files from a workspace you choose.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>PlansBar reads plan files from a workspace you choose.</string>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --sign - "${BUNDLE}"

echo "✓ Ready: ${BUNDLE}"
echo "  Run: open ${BUNDLE}"
