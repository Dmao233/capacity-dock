#!/usr/bin/env bash
# Build CapacityDock.app (ad-hoc signed) into .build/dist.
set -euo pipefail

VERSION="${1:-dev}"
BUNDLE_NAME="CapacityDock.app"
BUNDLE_ID="com.dmao233.capacity-dock"
EXECUTABLE_NAME="CapacityDock"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC_DIR="$ROOT"
DIST_DIR="${MAC_DIR}/.build/dist"
ICON_SOURCE="${ROOT}/assets/icon.png"

cd "${MAC_DIR}"

echo "▸ Building release binary..."
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
BUILT_BINARY="${BIN_PATH}/${EXECUTABLE_NAME}"

echo "▸ Assembling ${BUNDLE_NAME}..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${DIST_DIR}/${BUNDLE_NAME}/Contents/Resources"
BUNDLE="${DIST_DIR}/${BUNDLE_NAME}"
cp "${BUILT_BINARY}" "${BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
  ICONSET="${DIST_DIR}/AppIcon.iconset"
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
  cp "${ICON_SOURCE}" "${ICONSET}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET}" -o "${BUNDLE}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICONSET}"
fi

SPM_RESOURCE_BUNDLE="${BIN_PATH}/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
if [[ -d "${SPM_RESOURCE_BUNDLE}" ]]; then
  cp -R "${SPM_RESOURCE_BUNDLE}" "${BUNDLE}/Contents/Resources/"
fi
cp -R "${MAC_DIR}/Sources/CapacityDock/Resources/zh-Hans.lproj" "${BUNDLE}/Contents/Resources/"
cp "${ROOT}/LICENSE" "${BUNDLE}/Contents/Resources/LICENSE.txt"
cp "${ROOT}/NOTICE" "${BUNDLE}/Contents/Resources/NOTICE.txt"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hans</string></array>
    <key>CFBundleDisplayName</key>
    <string>Capacity Dock</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Capacity Dock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 CenFangyu / AgentSeal</string>
</dict>
</plist>
PLIST

echo "APPL????" > "${BUNDLE}/Contents/PkgInfo"
codesign --force --sign - --timestamp=none --deep "${BUNDLE}"
codesign --verify --deep --strict "${BUNDLE}"
echo "✓ ${BUNDLE}"
