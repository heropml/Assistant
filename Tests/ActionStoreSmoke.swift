import Darwin
import Foundation

@main
@MainActor
struct ActionStoreSmoke {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("RightClickAssistantExecutor-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let suiteName = "com.local.RightClickAssistant.executor-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("无法创建执行器测试偏好域")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try testRequestValidation(in: root)
        try testPreparedExecution(in: root, defaults: defaults)
        try testSameDirectoryPaste(in: root, defaults: defaults)
        try testTemplatePathConfinement(in: root, defaults: defaults)
        try testMissingTargetFails(in: root, defaults: defaults)
        try testScriptStandardInputIsEOF(in: root, defaults: defaults)
        testScriptOutputIsBounded(in: root, defaults: defaults)
        testInfiniteOutputCannotBypassTimeout(in: root, defaults: defaults)
        testScriptTimeoutTerminatesChildren(in: root, defaults: defaults)
        testSortingPersistence(defaults: defaults)

        print("宿主执行器测试通过")
    }

    private static func testSortingPersistence(defaults: UserDefaults) {
        let firstGroup = ActionGroup(id: "group-first", title: "第一组")
        let secondGroup = ActionGroup(id: "group-second", title: "第二组")
        let thirdGroup = ActionGroup(id: "group-third", title: "第三组")
        let firstAction = ConfiguredAction(
            id: "action-first",
            kind: .shell,
            title: "第一项",
            groupID: firstGroup.id,
            script: "true"
        )
        let secondAction = ConfiguredAction(
            id: "action-second",
            kind: .shell,
            title: "第二项",
            groupID: secondGroup.id,
            script: "true"
        )
        let thirdAction = ConfiguredAction(
            id: "action-third",
            kind: .shell,
            title: "第三项",
            groupID: thirdGroup.id,
            script: "true"
        )
        precondition(SharedPreferences.saveConfiguration(
            AssistantConfiguration(
                actions: [firstAction, secondAction, thirdAction],
                groups: [firstGroup, secondGroup, thirdGroup]
            ),
            defaults: defaults
        ))

        let store = ActionStore(defaults: defaults)
        store.move(actionID: thirdAction.id, before: firstAction.id)
        store.moveGroup(thirdGroup, by: -1)
        store.moveGroup(groupID: secondGroup.id, before: firstGroup.id)

        let expectedActionIDs = [thirdAction.id, firstAction.id, secondAction.id]
        let expectedGroupIDs = [secondGroup.id, firstGroup.id, thirdGroup.id]
        precondition(store.actions.map(\.id) == expectedActionIDs)
        precondition(store.groups.map(\.id) == expectedGroupIDs)

        let persisted = SharedPreferences.configuration(defaults: defaults)
        precondition(persisted.actions.map(\.id) == expectedActionIDs)
        precondition(persisted.groups.map(\.id) == expectedGroupIDs)

        let reloaded = ActionStore(defaults: defaults)
        precondition(reloaded.actions.map(\.id) == expectedActionIDs)
        precondition(reloaded.groups.map(\.id) == expectedGroupIDs)
    }

    private static func testPreparedExecution(in root: URL, defaults: UserDefaults) throws {
        let disabled = ConfiguredAction(
            id: "disabled-request",
            kind: .shell,
            title: "已停用请求",
            isEnabled: false,
            script: "echo disabled"
        )
        precondition(SharedPreferences.saveConfiguration(
            AssistantConfiguration(actions: [disabled], groups: []),
            defaults: defaults
        ))
        let disabledURL = SharedPreferences.executionURL(
            actionID: disabled.id,
            urls: [root],
            isContainer: false,
            defaults: defaults
        )!
        expectFailure(.actionDisabled) {
            _ = try HostActionExecutor.prepareExecution(from: disabledURL, defaults: defaults)
        }

        let valid = ConfiguredAction(
            id: "valid-request",
            kind: .shell,
            title: "有效请求",
            conditions: ActionConditions(
                allowsFiles: false,
                allowsFolders: false,
                allowsContainer: true
            ),
            script: #"touch "$1/prepared-execution""#
        )
        precondition(SharedPreferences.saveConfiguration(
            AssistantConfiguration(actions: [valid], groups: []),
            defaults: defaults
        ))
        let validURL = SharedPreferences.executionURL(
            actionID: valid.id,
            urls: [root],
            isContainer: true,
            defaults: defaults
        )!
        let prepared = try HostActionExecutor.prepareExecution(from: validURL, defaults: defaults)
        try HostActionExecutor.execute(action: prepared.action, urls: prepared.urls, defaults: defaults)
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("prepared-execution").path))
        expectFailure(.invalidRequest) {
            _ = try HostActionExecutor.prepareExecution(from: validURL, defaults: defaults)
        }
    }

    private static func testRequestValidation(in root: URL) throws {
        let file = root.appendingPathComponent("request.txt")
        try Data().write(to: file)

        let disabled = ConfiguredAction(
            kind: .shell,
            title: "已停用",
            isEnabled: false,
            script: "echo disabled"
        )
        expectFailure(.actionDisabled) {
            try HostActionExecutor.validateRequest(action: disabled, urls: [file], isContainer: false)
        }

        let containerOnly = ConfiguredAction(
            kind: .shell,
            title: "仅空白处",
            conditions: ActionConditions(
                allowsFiles: false,
                allowsFolders: false,
                allowsContainer: true
            ),
            script: "echo container"
        )
        try HostActionExecutor.validateRequest(action: containerOnly, urls: [root], isContainer: true)
        expectFailure(.conditionsNotMet) {
            try HostActionExecutor.validateRequest(action: containerOnly, urls: [file], isContainer: false)
        }
    }

    private static func testSameDirectoryPaste(in root: URL, defaults: UserDefaults) throws {
        let source = root.appendingPathComponent("same-directory.txt")
        try Data("keep-name".utf8).write(to: source)
        defaults.set([source.path], forKey: SharedPreferences.cutPathsKey)

        let paste = ConfiguredAction(
            kind: .builtIn,
            title: "粘贴",
            builtInOperation: .paste
        )
        try HostActionExecutor.execute(action: paste, urls: [root], defaults: defaults)

        precondition(FileManager.default.fileExists(atPath: source.path))
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("same-directory 2.txt").path))
        precondition(defaults.stringArray(forKey: SharedPreferences.cutPathsKey)?.isEmpty == true)
    }

    private static func testTemplatePathConfinement(in root: URL, defaults: UserDefaults) throws {
        let targetDirectory = root.appendingPathComponent("template-target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        let template = ConfiguredAction(
            kind: .template,
            title: "新建../outside",
            conditions: ActionConditions(allowsFiles: false, allowsFolders: true, allowsContainer: true),
            templateExtension: "txt",
            templateContent: "safe"
        )

        try HostActionExecutor.execute(
            action: template,
            urls: [targetDirectory],
            defaults: defaults,
            revealCreatedFiles: false
        )

        precondition(!FileManager.default.fileExists(atPath: outside.path))
        let created = try FileManager.default.contentsOfDirectory(at: targetDirectory, includingPropertiesForKeys: nil)
        precondition(created.count == 1)
        precondition(created[0].deletingLastPathComponent().standardizedFileURL == targetDirectory.standardizedFileURL)
    }

    private static func testMissingTargetFails(in root: URL, defaults: UserDefaults) throws {
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        let template = ConfiguredAction(
            kind: .template,
            title: "新建文件",
            templateExtension: "txt"
        )
        expectFailure(.missingTarget) {
            try HostActionExecutor.execute(
                action: template,
                urls: [missing],
                defaults: defaults,
                revealCreatedFiles: false
            )
        }
    }

    private static func testScriptOutputIsBounded(in root: URL, defaults: UserDefaults) {
        let script = ConfiguredAction(
            kind: .shell,
            title: "大输出",
            script: "yes x | head -c 100000; exit 7"
        )
        do {
            try HostActionExecutor.execute(action: script, urls: [root], defaults: defaults)
            preconditionFailure("大输出失败脚本不应成功")
        } catch let HostActionExecutor.ExecutionError.scriptFailed(message) {
            precondition(message.utf8.count <= 65_600)
            precondition(message.contains("输出已截断"))
        } catch {
            preconditionFailure("大输出脚本返回了错误类型：\(error)")
        }
    }

    private static func testScriptStandardInputIsEOF(in root: URL, defaults: UserDefaults) throws {
        let script = ConfiguredAction(
            kind: .shell,
            title: "标准输入为空",
            script: "cat >/dev/null"
        )
        try HostActionExecutor.execute(
            action: script,
            urls: [root],
            defaults: defaults,
            scriptTimeout: .seconds(1)
        )
    }

    private static func testScriptTimeoutTerminatesChildren(in root: URL, defaults: UserDefaults) {
        let directPIDFile = root.appendingPathComponent("timeout-direct.pid")
        let detachedPIDFile = root.appendingPathComponent("timeout-detached.pid")
        let readyFile = root.appendingPathComponent("timeout-ready")
        let script = ConfiguredAction(
            kind: .shell,
            title: "超时进程组",
            script: #"""
            sleep 30 >/dev/null 2>&1 &
            direct=$!
            printf '%s\n' "$direct" > "$1/timeout-direct.pid"

            /bin/sh -c '
              sleep 30 >/dev/null 2>&1 &
              printf "%s\n" "$!" > "$1/timeout-detached.pid"
            ' timeout-helper "$1"

            printf 'ready\n' > "$1/timeout-ready"
            wait "$direct"
            """#
        )
        expectFailure(.scriptTimedOut) {
            try HostActionExecutor.execute(
                action: script,
                urls: [root],
                defaults: defaults,
                scriptTimeout: .seconds(1)
            )
        }

        precondition(FileManager.default.fileExists(atPath: readyFile.path), "超时发生在测试进程布置完成之前")
        let directPID = readPID(directPIDFile)
        let detachedPID = readPID(detachedPIDFile)
        precondition(directPID != detachedPID)
        let survivors = processesStillAlive([directPID, detachedPID])
        precondition(survivors.isEmpty, "超时后仍有进程存活：\(survivors.sorted())")
    }

    private static func testInfiniteOutputCannotBypassTimeout(in root: URL, defaults: UserDefaults) {
        let script = ConfiguredAction(
            kind: .shell,
            title: "无限输出超时",
            script: "yes"
        )
        let startedAt = ProcessInfo.processInfo.systemUptime
        expectFailure(.scriptTimedOut) {
            try HostActionExecutor.execute(
                action: script,
                urls: [root],
                defaults: defaults,
                scriptTimeout: .milliseconds(100)
            )
        }
        precondition(
            ProcessInfo.processInfo.systemUptime - startedAt < 2,
            "持续输出绕过了脚本超时"
        )
    }

    private static func readPID(_ file: URL) -> pid_t {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let processID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              processID > 1 else {
            preconditionFailure("无效 PID 文件：\(file.lastPathComponent)")
        }
        return processID
    }

    private static func processesStillAlive(
        _ processIDs: Set<pid_t>,
        timeout: TimeInterval = 3
    ) -> Set<pid_t> {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var remaining = processIDs

        repeat {
            remaining = Set(remaining.filter { processID in
                while true {
                    errno = 0
                    if kill(processID, 0) == 0 { return true }
                    if errno == ESRCH { return false }
                    if errno == EINTR { continue }
                    return true
                }
            })
            if remaining.isEmpty {
                return []
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return remaining
    }

    private static func expectFailure(
        _ expectedError: HostActionExecutor.ExecutionError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            preconditionFailure("预期操作失败，但实际成功")
        } catch let error as HostActionExecutor.ExecutionError {
            precondition(error == expectedError, "错误类型不符：\(error)")
        } catch {
            preconditionFailure("返回了无关错误：\(error)")
        }
    }
}
