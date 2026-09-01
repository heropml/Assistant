#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP="${PROJECT_DIR}/dist/RightClickAssistant.app"
EXTENSION="${APP}/Contents/PlugIns/RightClickFinderExtension.appex"
ZIP="${PROJECT_DIR}/dist/RightClickAssistant-macOS.zip"
UNPACK_DIR="/tmp/RightClickAssistantVerify"
TEST_BINARY="/tmp/RightClickAssistantPreferencesSmoke"
EXECUTOR_TEST_BINARY="/tmp/RightClickAssistantExecutorSmoke"
ENTITLEMENTS_FILE="/tmp/RightClickAssistantExtensionEntitlements.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

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

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -u "/tmp/RightClickAssistantDebugDerivedData/Build/Products/Debug/RightClickAssistant.app" >/dev/null 2>&1 || :
fi

swiftc \
  -warnings-as-errors \
  -strict-concurrency=complete \
  -module-cache-path /tmp/RightClickAssistantModuleCache \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Tests/SharedPreferencesSmoke.swift" \
  -o "${TEST_BINARY}"
"${TEST_BINARY}"

swiftc \
  -warnings-as-errors \
  -strict-concurrency=complete \
  -module-cache-path /tmp/RightClickAssistantModuleCache \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/RightClickAssistant/ActionStore.swift" \
  "${PROJECT_DIR}/Tests/ActionStoreSmoke.swift" \
  -o "${EXECUTOR_TEST_BINARY}"
"${EXECUTOR_TEST_BINARY}"
"${EXECUTOR_TEST_BINARY}" 0<&- 1>&-

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP}"
/usr/bin/codesign --verify --strict --verbose=2 "${EXTENSION}"
/usr/bin/codesign -d --entitlements :- "${EXTENSION}" > "${ENTITLEMENTS_FILE}" 2>/dev/null

APP_SIGNATURE_INFO="$(/usr/bin/codesign -d --verbose=4 "${APP}" 2>&1)"
EXTENSION_SIGNATURE_INFO="$(/usr/bin/codesign -d --verbose=4 "${EXTENSION}" 2>&1)"
[[ "${APP_SIGNATURE_INFO}" == *"Signature=adhoc"* && "${APP_SIGNATURE_INFO}" == *"TeamIdentifier=not set"* ]]
[[ "${APP_SIGNATURE_INFO}" == *"runtime"* ]]
[[ "${EXTENSION_SIGNATURE_INFO}" == *"Signature=adhoc"* && "${EXTENSION_SIGNATURE_INFO}" == *"TeamIdentifier=not set"* ]]
[[ "${EXTENSION_SIGNATURE_INFO}" == *"runtime"* ]]

SANDBOX_ENABLED="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${ENTITLEMENTS_FILE}")"
SHARED_DOMAIN="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.shared-preference.read-write:0' "${ENTITLEMENTS_FILE}")"
[[ "${SANDBOX_ENABLED}" == "true" ]]
[[ "${SHARED_DOMAIN}" == "com.local.RightClickAssistant.shared" ]]
! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.shared-preference.read-write:1' "${ENTITLEMENTS_FILE}" >/dev/null 2>&1
! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.shared-preference.read-only' "${ENTITLEMENTS_FILE}" >/dev/null 2>&1

ARCHITECTURES="$(/usr/bin/lipo -archs "${APP}/Contents/MacOS/RightClickAssistant")"
[[ "${ARCHITECTURES}" == *arm64* && "${ARCHITECTURES}" == *x86_64* ]]
EXTENSION_ARCHITECTURES="$(/usr/bin/lipo -archs "${EXTENSION}/Contents/MacOS/RightClickFinderExtension")"
[[ "${EXTENSION_ARCHITECTURES}" == *arm64* && "${EXTENSION_ARCHITECTURES}" == *x86_64* ]]

EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${EXTENSION}/Contents/Info.plist")"
[[ "${EXTENSION_POINT}" == "com.apple.FinderSync" ]]

APP_ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${APP}/Contents/Info.plist")"
APP_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "${APP}/Contents/Info.plist")"
[[ "${APP_ICON_FILE}" == "AppIcon" && "${APP_ICON_NAME}" == "AppIcon" ]]
[[ -f "${APP}/Contents/Resources/AppIcon.icns" ]]
APP_BUNDLE_MTIME="$(/usr/bin/stat -f '%m' "${APP}")"
APP_ICON_MTIME="$(/usr/bin/stat -f '%m' "${APP}/Contents/Resources/AppIcon.icns")"
(( APP_BUNDLE_MTIME >= APP_ICON_MTIME ))
[[ -f "${APP}/Contents/Resources/Assets.car" ]]
[[ -f "${EXTENSION}/Contents/Resources/Assets.car" ]]
APP_ASSET_INFO="$(/usr/bin/assetutil --info "${APP}/Contents/Resources/Assets.car")"
EXTENSION_ASSET_INFO="$(/usr/bin/assetutil --info "${EXTENSION}/Contents/Resources/Assets.car")"
[[ "${APP_ASSET_INFO}" == *'"Name" : "AssistantMark"'* ]]
[[ "${APP_ASSET_INFO}" == *'"Template Mode" : "template"'* ]]
[[ "${EXTENSION_ASSET_INFO}" == *'"Name" : "AssistantMark"'* ]]
[[ "${EXTENSION_ASSET_INFO}" == *'"Template Mode" : "template"'* ]]
for ACTION_ICON_NAME in \
  "ActionCopyPath" \
  "ActionNewTextFile" \
  "ActionTerminal"; do
  print -r -- "${EXTENSION_ASSET_INFO}" \
    | /usr/bin/jq -e --arg name "${ACTION_ICON_NAME}" \
      'any(.[]; .Name == $name and ((.["Template Mode"] // "original") == "original"))' >/dev/null
done
for RESERVED_SYMBOL_NAME in \
  "point.topleft.down.to.point.bottomright.curvepath" \
  "doc.badge.plus" \
  "apple.terminal"; do
  ! print -r -- "${EXTENSION_ASSET_INFO}" \
    | /usr/bin/jq -e --arg name "${RESERVED_SYMBOL_NAME}" \
      'any(.[]; .Name == $name)' >/dev/null
done

/bin/rm -rf "${UNPACK_DIR}"
mkdir -p "${UNPACK_DIR}"
/usr/bin/ditto -x -k "${ZIP}" "${UNPACK_DIR}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${UNPACK_DIR}/RightClickAssistant.app"

print "完整验证通过（配置、执行器、大小图标、图标缓存刷新标记、菜单栏/Finder 模板图标、动作原色图标、Debug/Release 代码、双架构、嵌套扩展、本地签名、ZIP 解包）"
