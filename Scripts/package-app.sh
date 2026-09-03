#!/usr/bin/env bash
# Build CapacityDock.app (ad-hoc signed) plus a distributable zip + SHA-256.
#
# Usage:
#   Scripts/package-app.sh [<version>]
# Defaults to `dev` if no version is given. A leading `v` is stripped from
# CFBundleShortVersionString so `v0.1.0` and `0.1.0` produce the same bundle.
set -euo pipefail

VERSION_RAW="${1:-dev}"
VERSION="${VERSION_RAW#v}"
BUNDLE_NAME="CapacityDock.app"
BUNDLE_ID="com.dmao233.capacity-dock"
EXECUTABLE_NAME="CapacityDock"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Documents/ is often iCloud-synced; FinderInfo/fileprovider xattrs
# break codesign. Assemble on a local temp volume, then copy the zip back.
STAGE_DIR="$(mktemp -d /tmp/capacity-dock-pack.XXXXXX)"
DIST_DIR="${ROOT}/.build/dist"
ICON_SOURCE="${ROOT}/assets/icon.png"
trap 'rm -rf "${STAGE_DIR}"' EXIT

cd "${ROOT}"

echo "▸ Building universal release binary (arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

BIN_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
BUILT_BINARY="${BIN_PATH}/${EXECUTABLE_NAME}"
if [[ ! -x "${BUILT_BINARY}" ]]; then
  echo "Binary not found at ${BUILT_BINARY}" >&2
  exit 1
fi

echo "▸ Assembling ${BUNDLE_NAME}..."
export COPYFILE_DISABLE=1
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
BUNDLE="${STAGE_DIR}/${BUNDLE_NAME}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
ditto --norsrc --noextattr "${BUILT_BINARY}" "${BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
  ICONSET="${STAGE_DIR}/AppIcon.iconset"
  mkdir -p "${ICONSET}"
  sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_512x512.png" >/dev/null
  cp "${ICON_SOURCE}" "${ICONSET}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET}" -o "${BUNDLE}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICONSET}"
fi

SPM_RESOURCE_BUNDLE="${BIN_PATH}/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
if [[ -d "${SPM_RESOURCE_BUNDLE}" ]]; then
  ditto --norsrc --noextattr "${SPM_RESOURCE_BUNDLE}" "${BUNDLE}/Contents/Resources/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
fi
ditto --norsrc --noextattr "${ROOT}/Sources/CapacityDock/Resources/zh-Hans.lproj" "${BUNDLE}/Contents/Resources/zh-Hans.lproj"
ditto --norsrc --noextattr "${ROOT}/LICENSE" "${BUNDLE}/Contents/Resources/LICENSE.txt"
ditto --norsrc --noextattr "${ROOT}/NOTICE" "${BUNDLE}/Contents/Resources/NOTICE.txt"

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

printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

echo "▸ Ad-hoc signing..."
xattr -cr "${BUNDLE}" || true
find "${BUNDLE}" \( -name '._*' -o -name '.DS_Store' \) -delete
dot_clean -m "${BUNDLE}" 2>/dev/null || true
codesign --force --sign - --timestamp=none --deep "${BUNDLE}"
codesign --verify --deep --strict "${BUNDLE}"

BUILT_EXE="${BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
if command -v vtool >/dev/null 2>&1; then
  MINOS_LINES=$(vtool -show-build "${BUILT_EXE}" 2>/dev/null | awk '/minos/{print $2}')
  if [[ -n "${MINOS_LINES}" ]]; then
    BAD_MINOS=$(printf '%s\n' "${MINOS_LINES}" | grep -v '^14\.0$' || true)
    if [[ -n "${BAD_MINOS}" ]]; then
      echo "✗ Expected minos 14.0 for every arch slice, found: ${BAD_MINOS}" >&2
      exit 1
    fi
    echo "  minos 14.0 confirmed."
  fi
fi

ZIP_NAME="CapacityDock-${VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
echo "▸ Packaging ${ZIP_NAME}..."
(
  cd "${STAGE_DIR}"
  COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "${BUNDLE_NAME}" "${ZIP_NAME}"
  shasum -a 256 "${ZIP_NAME}" > "${ZIP_NAME}.sha256"
)
mkdir -p "${DIST_DIR}"
ditto --norsrc --noextattr "${STAGE_DIR}/${ZIP_NAME}" "${ZIP_PATH}"
ditto --norsrc --noextattr "${STAGE_DIR}/${ZIP_NAME}.sha256" "${ZIP_PATH}.sha256"
ditto --norsrc --noextattr "${BUNDLE}" "${DIST_DIR}/${BUNDLE_NAME}"

echo ""
echo "✓ ${DIST_DIR}/${BUNDLE_NAME}"
echo "✓ ${ZIP_PATH}"
cat "${ZIP_PATH}.sha256"
ls -lh "${DIST_DIR}"
