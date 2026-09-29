import AppKit
import CryptoKit
import Foundation

struct GiteeRelease: Decodable {
    let tagName: String
    let assets: [GiteeAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GiteeAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum UpdateStatus {
    case upToDate
    case available(version: String, downloadURL: URL?, releaseURL: URL)
    case failed(String)
}

enum Updater {
    // Update source is Gitee — GitHub is slow/unreliable for users in mainland China.
    static let repoOwner = "xiaohe529"
    // 仓库实际拼写：FocusPause（Gitee 仓库名对大小写敏感，必须与实际创建的大小写一致）
    static let repoName = "FocusPause"
    static let apiURL = "https://gitee.com/api/v5/repos/\(repoOwner)/\(repoName)/releases"
    static let releasePageURL = "https://gitee.com/\(repoOwner)/\(repoName)/releases"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func checkForUpdates() async -> UpdateStatus {
        guard let url = URL(string: apiURL) else { return .failed("无效的更新检查地址") }
        var request = URLRequest(url: url)
        request.setValue("FocusPause/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("无法连接更新服务器，请检查网络后重试")
            }
            let releases = try JSONDecoder().decode([GiteeRelease].self, from: data)
            // Gitee's /releases/latest is unreliable (it returned an older release here),
            // so enumerate all releases and pick the highest semantic version ourselves.
            let latest = releases
                .map { (release: $0, version: $0.tagName.replacingOccurrences(of: "v", with: "")) }
                .max { compareVersions($0.version, $1.version) == .orderedAscending }
            guard let latest else { return .failed("暂无可用版本信息") }
            if compareVersions(currentVersion, latest.version) == .orderedAscending {
                // Prefer the packaged app asset; skip Gitee's auto-generated source archives
                // (v1.1.3.zip / .tar.gz) by matching the "FocusPause" prefix.
                let asset = latest.release.assets.first { $0.name.hasPrefix("FocusPause") && $0.name.hasSuffix(".dmg") }
                    ?? latest.release.assets.first { $0.name.hasPrefix("FocusPause") && $0.name.hasSuffix(".zip") }
                let releaseURL = URL(string: "\(releasePageURL)/tag/\(latest.release.tagName)") ?? URL(string: releasePageURL)!
                return .available(version: latest.version, downloadURL: asset?.browserDownloadURL, releaseURL: releaseURL)
            } else {
                return .upToDate
            }
        } catch {
            return .failed("检查更新失败：\(error.localizedDescription)")
        }
    }

    static func download(_ url: URL, to destination: URL) async throws {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    /// Downloads the release asset to the user's Downloads folder, verifies it when
    /// the release publishes a matching `.sha256` asset, then opens it. A DMG is
    /// mounted so the drag-to-Applications window appears immediately; any other
    /// archive is revealed in Finder instead. Returns an error message on failure,
    /// or nil on success.
    static func downloadAndOpen(_ url: URL) async -> String? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent(url.lastPathComponent)
        do {
            try await download(url, to: downloads)
            if let problem = await verifyChecksum(for: downloads) {
                try? FileManager.default.removeItem(at: downloads)
                return problem
            }
            if downloads.pathExtension.lowercased() == "dmg" {
                // Mount and show the installer window; the user drags across without
                // a second double-click in Finder.
                NSWorkspace.shared.open(downloads)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([downloads])
            }
            return nil
        } catch {
            return "下载失败：\(error.localizedDescription)"
        }
    }

    /// Fetches `<asset>.sha256` from the same release and compares it against the
    /// downloaded file. Returns nil when the file matches or when no checksum
    /// asset is published (older releases predate this).
    private static func verifyChecksum(for file: URL) async -> String? {
        guard let remote = remoteChecksumURL(for: file) else { return nil }
        guard let fetched = try? await URLSession.shared.data(from: remote) else { return nil }
        let (data, response) = fetched
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let expected = Self.extractDigest(from: text)
        guard let expected else { return nil }
        let actual = sha256Hex(of: file)
        guard actual.lowercased() == expected.lowercased() else {
            return "安装包校验失败，可能在下载中损坏，请重试。"
        }
        return nil
    }

    /// Pulls the 64-hex-character digest out of a `sha256sum`-style text body.
    private static func extractDigest(from text: String) -> String? {
        for line in text.split(separator: "\n") {
            let token = line.split(separator: " ").first.map(String.init) ?? ""
            if token.count == 64 && token.allSatisfy(\.isHexDigit) { return token }
        }
        return nil
    }

    /// Derives the release-hosted `.sha256` URL from a local download path by
    /// pointing back at the Gitee release download endpoint.
    private static func remoteChecksumURL(for file: URL) -> URL? {
        guard let tag = releaseTagFromAssetName(file.lastPathComponent) else { return nil }
        return URL(string: "\(releasePageURL)/download/\(tag)/\(file.lastPathComponent).sha256")
    }

    /// `FocusPause-v1.0.7.dmg` -> `v1.0.7`
    private static func releaseTagFromAssetName(_ name: String) -> String? {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard let last = parts.last else { return nil }
        let stem = last.split(separator: ".").first.map(String.init) ?? ""
        return stem.hasPrefix("v") ? stem : nil
    }

    private static func sha256Hex(of file: URL) -> String {
        guard let data = try? Data(contentsOf: file) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = normalizedVersion(a).split(separator: ".").map { Int($0) ?? 0 }
        let pb = normalizedVersion(b).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(pa.count, pb.count)
        for i in 0..<count {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }
}
extension Updater {
    /// Removes optional whitespace and a single leading `v`; leaves pre-release
    /// suffixes to the numeric fallback rather than corrupting digits inside a tag.
    static func normalizedVersion(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if result.hasPrefix("v") {
            result.removeFirst()
        }
        return result
    }
}
