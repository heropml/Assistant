#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/RightClickAssistantTests.XXXXXX")"
trap '/bin/rm -rf "${TEST_DIR}"' EXIT

SWIFT_FLAGS=(
  -warnings-as-errors
  -swift-version 6
  -strict-concurrency=complete
  -module-cache-path "${TEST_DIR}/ModuleCache"
  -target "$(uname -m)-apple-macos14.0"
)
if [[ -n "${SDKROOT:-}" ]]; then
  SWIFT_FLAGS+=(-sdk "${SDKROOT}")
fi

swiftc "${SWIFT_FLAGS[@]}" \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}/Tests/SharedPreferencesSmoke.swift" \
  -o "${TEST_DIR}/PreferencesSmoke"
"${TEST_DIR}/PreferencesSmoke"

swiftc "${SWIFT_FLAGS[@]}" \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}/RightClickAssistant/ActionStore.swift" \
  "${PROJECT_DIR}/Tests/ActionStoreSmoke.swift" \
  -o "${TEST_DIR}/ExecutorSmoke"
"${TEST_DIR}/ExecutorSmoke"
"${TEST_DIR}/ExecutorSmoke" 0<&- 1>&-

swiftc "${SWIFT_FLAGS[@]}" \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}/RightClickAssistant/UpdateService.swift" \
  "${PROJECT_DIR}/Tests/UpdateSmoke.swift" \
  -o "${TEST_DIR}/UpdateSmoke"
"${TEST_DIR}/UpdateSmoke"

swiftc "${SWIFT_FLAGS[@]}" \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}/Tests/LocalizationSmoke.swift" \
  -o "${TEST_DIR}/LocalizationSmoke"
"${TEST_DIR}/LocalizationSmoke"

swiftc "${SWIFT_FLAGS[@]}" -typecheck \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}"/RightClickAssistant/*.swift
swiftc "${SWIFT_FLAGS[@]}" -typecheck -application-extension \
  "${PROJECT_DIR}/Shared/QuickAction.swift" \
  "${PROJECT_DIR}/Shared/Localization.swift" \
  "${PROJECT_DIR}/RightClickFinderExtension/FinderSync.swift"

print "核心验证通过（配置、并发执行、文件保护、菜单条件、Swift 6 严格并发、主应用和扩展类型检查）"
