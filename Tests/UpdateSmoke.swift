import CryptoKit
import Foundation

private final class ManifestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.path == "/slow" { return }
        let status = url.path == "/missing" ? 404 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: url.path == "/bad" ? Data("bad-json".utf8) : UpdateSmoke.manifestData())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct UpdateSmoke {
    static func manifestData(version: String = "1.1.0", hash: String? = nil, size: Int = 3, urls: Any = ["https://github.com/heropml/Assistant/releases/download/v1.1.0/app.dmg"]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "version": version, "notes": "更新说明", "url_mac": urls, "arch_mac": "arm64",
            "sha256_mac": hash ?? SHA256.hash(data: Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(), "size_mac": size
        ])
    }

    static func main() async throws {
        for (older, newer) in [("1.0.0", "1.0.1"), ("1.9.0", "1.10.0"), ("1.0.0-rc1", "1.0.0"),
                                ("1.0.0-rc2", "1.0.0-rc10"), ("1.0.0-beta.2", "1.0.0-beta.10"), ("1.0.0", "2.0.0")] {
            precondition(AppVersion(older)! < AppVersion(newer)!)
            precondition(!(AppVersion(newer)! < AppVersion(older)!))
        }
        precondition(AppVersion("v1.0") == AppVersion("1.0.0+build.21"))
        precondition(AppVersion("1.0.0.0") == AppVersion("1.0.0"))
        for value in ["", "v", "garbage", "1..0", "1.0.-1", "1.0.0-", "-1.0.0"] {
            precondition(AppVersion(value) == nil, "无效版本：\(value)")
        }
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(UpdateManifest.self, from: manifestData())
        let newer = try manifest.isNewer(than: "1.0.0")
        let same = try manifest.isNewer(than: "1.1.0")
        let older = try manifest.isNewer(than: "2.0.0")
        precondition(newer && !same && !older)
        let candidates = try decoder.decode(UpdateManifest.self, from: manifestData(urls: [
            "http://example.com/app.dmg", "https://gitee.com/app.dmg", "https://github.com/repo/app.dmg", "https://github.com/repo/app.dmg"
        ]))
        precondition(candidates.urls.count == 2 && candidates.urls[0].host == "github.com")
        _ = try decoder.decode(UpdateManifest.self, from: manifestData(urls: "https://github.com/repo/app.dmg"))
        for invalid in [manifestData(hash: "bad"), manifestData(size: 0), manifestData(version: "oops"), manifestData(urls: "http://github.com/app.dmg"), manifestData(urls: "https://github.com/error.html")] {
            do { _ = try decoder.decode(UpdateManifest.self, from: invalid); preconditionFailure("接受了无效清单") } catch {}
        }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        try UpdateClient.verify(file: file, manifest: manifest)
        try Data("abd".utf8).write(to: file)
        do { try UpdateClient.verify(file: file, manifest: manifest); preconditionFailure("未发现内容被修改") }
        catch UpdateError.checksumMismatch {}
        try Data("ab".utf8).write(to: file)
        do { try UpdateClient.verify(file: file, manifest: manifest); preconditionFailure("未发现下载截断") }
        catch UpdateError.sizeMismatch {}
        try Data("abcd".utf8).write(to: file)
        do { try UpdateClient.verify(file: file, manifest: manifest); preconditionFailure("未发现安装包过大") }
        catch UpdateError.sizeMismatch {}

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checked = try await UpdateClient.check(session: session, url: URL(string: "https://updates.example/manifest")!)
        precondition(checked.version == "1.1.0")
        do {
            _ = try await UpdateClient.check(session: session, url: URL(string: "https://updates.example/missing")!)
            preconditionFailure("404 应提示未发布或仓库不可公开访问")
        } catch UpdateError.unavailable {}
        do {
            _ = try await UpdateClient.check(session: session, url: URL(string: "https://updates.example/bad")!)
            preconditionFailure("无效响应必须失败")
        } catch is DecodingError {}
        let slow = Task { try await UpdateClient.check(session: session, url: URL(string: "https://updates.example/slow")!) }
        try await Task.sleep(for: .milliseconds(30))
        slow.cancel()
        do { _ = try await slow.value; preconditionFailure("取消检查未生效") }
        catch is CancellationError {} catch let error as URLError { precondition(error.code == .cancelled) }
        print("更新测试通过（版本比较、清单、HTTPS、校验、网络错误与取消）")
    }
}
