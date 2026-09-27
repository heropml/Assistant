import AppKit
import Foundation

@MainActor
enum ApplicationRestart {
    enum RestartError: LocalizedError {
        case actionsRunning
        case invalidApplication

        var errorDescription: String? {
            switch self {
            case .actionsRunning: L10n.tr("有动作正在执行，请等待完成后再重启。")
            case .invalidApplication: L10n.tr("无法定位当前应用，请退出后从“应用程序”重新打开。")
            }
        }
    }

    // Wait for this instance to exit, then reopen its exact bundle path.
    // Arguments carry paths separately from shell code, including quotes/spaces.
    static let helperScript = #"""
    count=0
    while /bin/kill -0 "$1" 2>/dev/null; do
        [ "$count" -lt 100 ] || exit 1
        /bin/sleep 0.1
        count=$((count + 1))
    done
    exec /usr/bin/open -n "$2"
    """#

    static func restart(runningActionCount: Int) throws {
        guard runningActionCount == 0 else { throw RestartError.actionsRunning }
        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app",
              let executableURL = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RestartError.invalidApplication
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", helperScript, "RightClickAssistant-Relaunch",
                            String(ProcessInfo.processInfo.processIdentifier), applicationURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        // If launching the helper fails, keep the app open and report the error.
        try helper.run()
        UserDefaults.standard.synchronize()
        SharedPreferences.defaults.synchronize()
        NSApplication.shared.terminate(nil)
    }
}
