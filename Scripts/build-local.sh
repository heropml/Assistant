#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DERIVED_DATA_DIR="${PROJECT_DIR}/dist/DerivedData"
SOURCE_APP="${DERIVED_DATA_DIR}/Build/Products/Release/RightClickAssistant.app"
OUTPUT_APP="${PROJECT_DIR}/dist/RightClickAssistant.app"
OUTPUT_ZIP="${PROJECT_DIR}/dist/RightClickAssistant-macOS.zip"

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
/usr/bin/codesign --verify --deep --strict --verbose=2 "${OUTPUT_APP}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_APP}" "${OUTPUT_ZIP}"

print ""
print "本地版已生成："
print "  ${OUTPUT_APP}"
print "  ${OUTPUT_ZIP}"
