#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DERIVED_DATA_DIR="${PROJECT_DIR}/dist/DerivedData"
SOURCE_APP="${DERIVED_DATA_DIR}/Build/Products/Release/RightClickAssistant.app"
OUTPUT_APP="${PROJECT_DIR}/dist/RightClickAssistant.app"
OUTPUT_ZIP="${PROJECT_DIR}/dist/RightClickAssistant-macOS.zip"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

mkdir -p "${PROJECT_DIR}/dist"

xcodebuild \
  -project "${PROJECT_DIR}/RightClickAssistant.xcodeproj" \
  -scheme RightClickAssistant \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  -quiet \
  build

/bin/rm -rf "${OUTPUT_APP}"
/bin/rm -f "${OUTPUT_ZIP}"
/usr/bin/ditto "${SOURCE_APP}" "${OUTPUT_APP}"
# Finder and Dock key their icon cache partly by the app bundle directory's
# modification time. Xcode can leave that directory timestamp unchanged even
# when AppIcon.icns was rebuilt, so explicitly mark the packaged app as fresh.
/usr/bin/touch "${OUTPUT_APP}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${OUTPUT_APP}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_APP}" "${OUTPUT_ZIP}"

# xcodebuild registers local products with LaunchServices, which can leave
# multiple copies of the same Finder extension competing with /Applications.
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -u "${SOURCE_APP}" >/dev/null 2>&1 || :
  "${LSREGISTER}" -u "${OUTPUT_APP}" >/dev/null 2>&1 || :
fi

print ""
print "本地版已生成："
print "  ${OUTPUT_APP}"
print "  ${OUTPUT_ZIP}"
