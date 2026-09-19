import AppKit
import Combine
import CryptoKit
import Foundation

struct AppVersion: Comparable, Sendable {
    let components: [Int]
    let prerelease: [String]

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    init?(_ value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        let core = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !numbers.isEmpty, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }) else { return nil }
        var components = numbers.map { Int($0)! }
        while components.count < 3 { components.append(0) }
        while components.count > 3 && components.last == 0 { components.removeLast() }
        let prerelease = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard prerelease.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } }) else { return nil }
        self.components = components
        self.prerelease = prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.components != rhs.components { return lhs.components.lexicographicallyPrecedes(rhs.components) }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            if let a = Int(left), let b = Int(right) { return a < b }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left.compare(right, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct UpdateManifest: Decodable, Sendable {
    let version: String
    let notes: String
    let urls: [URL]
    let sha256: String
    let size: Int64
    let architecture: String

    enum CodingKeys: String, CodingKey {
        case version, notes
        case urls = "url_mac", sha256 = "sha256_mac", size = "size_mac", architecture = "arch_mac"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        guard AppVersion(version) != nil else { throw UpdateError.invalidManifest }
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let candidates: [String]
        if let single = try? values.decode(String.self, forKey: .urls) { candidates = [single] }
        else { candidates = try values.decode([String].self, forKey: .urls) }
        var seen = Set<URL>()
        urls = candidates.compactMap { raw in
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.lowercased() == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.pathExtension.lowercased() == "dmg",
                  seen.insert(url).inserted else { return nil }
            return url
        }.sorted { Self.isGitHub($0) && !Self.isGitHub($1) }
        sha256 = try values.decode(String.self, forKey: .sha256).lowercased()
        size = try values.decode(Int64.self, forKey: .size)
        architecture = try values.decodeIfPresent(String.self, forKey: .architecture) ?? "arm64"
        guard !urls.isEmpty, size > 0, sha256.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              ["arm64", "universal"].contains(architecture) else { throw UpdateError.invalidManifest }
    }

    private static func isGitHub(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    func isNewer(than local: String) throws -> Bool {
        guard let remote = AppVersion(version), let current = AppVersion(local) else { throw UpdateError.invalidManifest }
        return remote > current
    }
}

enum UpdateError: LocalizedError {
    case invalidManifest, unavailable, http(Int), sizeMismatch, checksumMismatch, openFailed, wrongArchitecture

    var errorDescription: String? {
        switch self {
        case .invalidManifest: L10n.tr("更新清单无效：请检查版本、HTTPS 安装包地址、SHA-256 和文件大小。")
        case .unavailable: L10n.tr("尚未发布更新清单，或更新仓库不可公开访问。")
        case .http(let status): L10n.tr("更新服务器返回 HTTP %@，请稍后重试。", String(describing: status))
        case .sizeMismatch: L10n.tr("安装包大小与更新清单不符，请重新下载。")
        case .checksumMismatch: L10n.tr("安装包 SHA-256 校验失败，已丢弃下载文件。")
        case .openFailed: L10n.tr("无法打开安装包，请从 GitHub 发布页下载安装。")
        case .wrongArchitecture: L10n.tr("此安装包仅支持 Apple Silicon（arm64）。")
        }
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expectedSize: Int64
    let progress: @Sendable (Double) -> Void

    init(expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedSize { downloadTask.cancel() }
        progress(min(1, Double(totalBytesWritten) / Double(expectedSize)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

enum UpdateClient {
    static let manifestURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "RCAUpdateManifestURL") as? String
        ?? "https://raw.githubusercontent.com/heropml/Assistant/main/latest.json")!
    static let releasesURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "RCAReleasesURL") as? String
        ?? "https://github.com/heropml/Assistant/releases")!

    static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidManifest }
        if http.statusCode == 404 { throw UpdateError.unavailable }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }
        guard http.url?.scheme?.lowercased() == "https" else { throw UpdateError.invalidManifest }
    }

    static func check(session: URLSession = .shared, url: URL = manifestURL) async throws -> UpdateManifest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("RightClickAssistant/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        guard data.count <= 1_048_576 else { throw UpdateError.invalidManifest }
        return try JSONDecoder().decode(UpdateManifest.self, from: data)
    }

    static func verify(file: URL, manifest: UpdateManifest) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        var bytes: Int64 = 0
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes += Int64(chunk.count)
            guard bytes <= manifest.size else { throw UpdateError.sizeMismatch }
            digest.update(data: chunk)
        }
        guard bytes == manifest.size else { throw UpdateError.sizeMismatch }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == manifest.sha256 else { throw UpdateError.checksumMismatch }
    }

    static func download(_ manifest: UpdateManifest, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        #if !arch(arm64)
        guard manifest.architecture == "universal" else { throw UpdateError.wrongArchitecture }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 1800
        let delegate = UpdateDownloadDelegate(expectedSize: manifest.size, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var lastError: Error = UpdateError.unavailable
        for url in manifest.urls {
            do {
                try Task.checkCancellation()
                progress(0)
                let (temporary, response) = try await session.download(from: url, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try validateResponse(response)
                try verify(file: temporary, manifest: manifest)
                try Task.checkCancellation()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RightClickAssistantUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent("RightClickAssistant.dmg")
                do { try FileManager.default.moveItem(at: temporary, to: destination) }
                catch { try? FileManager.default.removeItem(at: directory); throw error }
                return destination
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        throw lastError
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    enum State {
        case idle, checking, latest, available, downloading(Double), ready(URL), failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var release: UpdateManifest?
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    var isBusy: Bool {
        switch state { case .checking, .downloading: true; default: false }
    }

    func check() {
        cancel()
        release = nil
        state = .checking
        let id = operationID
        task = Task {
            do {
                let manifest = try await UpdateClient.check()
                try Task.checkCancellation()
                guard operationID == id else { return }
                release = manifest
                state = try manifest.isNewer(than: AppVersion.current) ? .available : .latest
            } catch {
                guard !Task.isCancelled, operationID == id else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func download() {
        guard let release, !isBusy else { return }
        operationID = UUID()
        let id = operationID
        state = .downloading(0)
        task = Task { [self] in
            do {
                let file = try await UpdateClient.download(release) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.operationID == id,
                              case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                guard !Task.isCancelled, operationID == id else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    return
                }
                guard NSWorkspace.shared.open(file) else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    throw UpdateError.openFailed
                }
                state = .ready(file)
            } catch {
                guard !Task.isCancelled, operationID == id else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationID = UUID()
        task?.cancel()
        task = nil
        if isBusy { state = release == nil ? .idle : .available }
    }
}
