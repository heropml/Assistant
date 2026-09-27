import Foundation

@main
@MainActor
struct ApplicationRestartSmoke {
    static func main() throws {
        do {
            try ApplicationRestart.restart(runningActionCount: 1)
            preconditionFailure("运行中的动作必须阻止重启")
        } catch ApplicationRestart.RestartError.actionsRunning { }
        do {
            try ApplicationRestart.restart(runningActionCount: 0)
            preconditionFailure("非应用进程不能重启")
        } catch ApplicationRestart.RestartError.invalidApplication { }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("opened-path")
        let path = root.appendingPathComponent("右键 助手 '$() `echo test` \".app").path
        let original = Process()
        original.executableURL = URL(fileURLWithPath: "/bin/sleep")
        original.arguments = ["5"]
        try original.run()
        defer {
            if original.isRunning { original.terminate(); original.waitUntilExit() }
        }

        // Record the launch request instead of opening a real app during tests.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", ApplicationRestart.helperScript.replacingOccurrences(
            of: #"exec /usr/bin/open -n "$2""#,
            with: #"printf '%s' "$2" > "$3""#
        ), "RestartTest", String(original.processIdentifier), path, output.path]
        try helper.run()
        Thread.sleep(forTimeInterval: 0.15)
        precondition(!FileManager.default.fileExists(atPath: output.path), "旧进程退出前不能重开")
        original.terminate()
        original.waitUntilExit()
        helper.waitUntilExit()
        precondition(helper.terminationStatus == 0)
        let reopenedPath = try String(contentsOf: output, encoding: .utf8)
        precondition(reopenedPath == path, "含空格、引号及 Shell 字符的路径必须原样传递")
        print("应用重启测试通过（运行任务保护、等待退出、精确路径和引号转义）")
    }
}
