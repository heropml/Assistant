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
/usr/bin/codesign --verify --deep --strict "${APP}"
[[ "$(/usr/bin/lipo -archs "${APP}/Contents/MacOS/RightClickAssistant")" == arm64 ]]
[[ "$(/usr/bin/lipo -archs "${APP}/Contents/PlugIns/RightClickFinderExtension.appex/Contents/MacOS/RightClickFinderExtension")" == arm64 ]]

DMG="${PROJECT_DIR}/dist/RightClickAssistant_v${VERSION}_arm64.dmg"
/usr/bin/ditto "${APP}" "${STAGING_DIR}/RightClickAssistant.app"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"
/usr/bin/hdiutil create -volname "右键助手 ${VERSION}" -srcfolder "${STAGING_DIR}" -format UDZO -ov "${DMG}"
/usr/bin/hdiutil verify "${DMG}"

python3 - "${DMG}" "${VERSION}" "${REPOSITORY}" "${NOTES}" "${PROJECT_DIR}/dist/latest.json" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

artifact, version, repository, notes, output = sys.argv[1:]
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
    raise SystemExit('无效 GitHub 仓库名称')
path = Path(artifact)
with path.open('rb') as stream:
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
manifest = {
    'version': version,
    'url_mac': [f'https://github.com/{repository}/releases/download/v{version}/{quote(path.name)}'],
    'arch_mac': 'arm64',
    'sha256_mac': digest.hexdigest(),
    'size_mac': path.stat().st_size,
    'notes': notes,
}
Path(output).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
PY
print "ARM 更新安装包：${DMG}"
print "待发布清单：${PROJECT_DIR}/dist/latest.json"
