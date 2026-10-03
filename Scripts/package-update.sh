#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP="${PROJECT_DIR}/dist/RightClickAssistant.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
REPOSITORY="${RCA_RELEASE_REPOSITORY:-heropml/Assistant}"
NOTES="${1:-右键助手更新}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/RightClickAssistantDMG.XXXXXX")"
trap '/bin/rm -rf "${STAGING_DIR}"' EXIT

[[ "${VERSION}" == [0-9]* && "${VERSION}" != *[^0-9.]* ]] || { print -u2 "安装包版本必须为正式数字版本"; exit 1; }
[[ "${REPOSITORY}" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || { print -u2 "无效 GitHub 仓库名称"; exit 1; }
/usr/bin/codesign --verify --deep --strict "${APP}"
[[ "$(/usr/bin/lipo -archs "${APP}/Contents/MacOS/RightClickAssistant")" == arm64 ]]
[[ "$(/usr/bin/lipo -archs "${APP}/Contents/PlugIns/RightClickFinderExtension.appex/Contents/MacOS/RightClickFinderExtension")" == arm64 ]]

DMG="${PROJECT_DIR}/dist/RightClickAssistant_v${VERSION}_arm64.dmg"
/usr/bin/ditto "${APP}" "${STAGING_DIR}/RightClickAssistant.app"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"
/usr/bin/hdiutil create -volname "右键助手 ${VERSION}" -srcfolder "${STAGING_DIR}" -format UDZO -ov "${DMG}"
/usr/bin/hdiutil verify "${DMG}"

SHA256="$(/usr/bin/shasum -a 256 "${DMG}" | /usr/bin/awk '{print $1}')"
SIZE="$(/usr/bin/stat -f '%z' "${DMG}")"
URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}/${DMG:t}"

# JavaScript for Automation ships with macOS, so packaging needs no Python.
# JSON.stringify keeps URLs and Chinese notes readable in the committed manifest.
MANIFEST_SCRIPT="${STAGING_DIR}/manifest.js"
/bin/cat > "${MANIFEST_SCRIPT}" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const [version, url, sha256, size, notes, output] = argv;
  const manifest = {
    version: version,
    url_mac: [url],
    arch_mac: 'arm64',
    sha256_mac: sha256,
    size_mac: Number(size),
    notes: notes,
  };
  const text = $(JSON.stringify(manifest, null, 2) + '\n');
  if (!text.writeToFileAtomicallyEncodingError(output, true, $.NSUTF8StringEncoding, null)) {
    throw new Error('无法写入更新清单');
  }
}
JS
/usr/bin/osascript -l JavaScript "${MANIFEST_SCRIPT}" \
  "${VERSION}" "${URL}" "${SHA256}" "${SIZE}" "${NOTES}" "${PROJECT_DIR}/dist/latest.json"
print "ARM 更新安装包：${DMG}"
print "待发布清单：${PROJECT_DIR}/dist/latest.json"
