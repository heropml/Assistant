#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP="${PROJECT_DIR}/dist/RightClickAssistant.app"
EXTENSION="${APP}/Contents/PlugIns/RightClickFinderExtension.appex"
ZIP="${PROJECT_DIR}/dist/RightClickAssistant-macOS.zip"
UNPACK_DIR="/tmp/RightClickAssistantVerify"
TEST_BINARY="/tmp/RightClickAssistantPreferencesSmoke"
ENTITLEMENTS_FILE="/tmp/RightClickAssistantExtensionEntitlements.plist"

"${PROJECT_DIR}/Scripts/build-local.sh"

xcodebuild \
  -project "${PROJECT_DIR}/RightClickAssistant.xcodeproj" \
  -scheme RightClickAssistant \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/RightClickAssistantDebugDerivedData \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  -quiet \
  build

swiftc \
  -module-cache-path /tmp/RightClickAssistantModuleCache \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Tests/SharedPreferencesSmoke.swift" \
  -o "${TEST_BINARY}"
"${TEST_BINARY}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP}"
/usr/bin/codesign --verify --strict --verbose=2 "${EXTENSION}"
/usr/bin/codesign -d --entitlements :- "${EXTENSION}" > "${ENTITLEMENTS_FILE}" 2>/dev/null

SANDBOX_ENABLED="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${ENTITLEMENTS_FILE}")"
SHARED_DOMAIN="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.shared-preference.read-only:0' "${ENTITLEMENTS_FILE}")"
[[ "${SANDBOX_ENABLED}" == "true" ]]
[[ "${SHARED_DOMAIN}" == "com.local.RightClickAssistant.shared" ]]

ARCHITECTURES="$(/usr/bin/lipo -archs "${APP}/Contents/MacOS/RightClickAssistant")"
[[ "${ARCHITECTURES}" == *arm64* && "${ARCHITECTURES}" == *x86_64* ]]

EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${EXTENSION}/Contents/Info.plist")"
[[ "${EXTENSION_POINT}" == "com.apple.FinderSync" ]]

/bin/rm -rf "${UNPACK_DIR}"
mkdir -p "${UNPACK_DIR}"
/usr/bin/ditto -x -k "${ZIP}" "${UNPACK_DIR}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${UNPACK_DIR}/RightClickAssistant.app"

print "完整验证通过（配置、Debug/Release 代码、双架构、嵌套扩展、本地签名、ZIP 解包）"
