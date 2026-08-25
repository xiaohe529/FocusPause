import AppKit
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

    /// Downloads the release asset to the user's Downloads folder and reveals it
    /// in Finder. Returns an error message on failure, or nil on success.
    static func downloadAndOpen(_ url: URL) async -> String? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent(url.lastPathComponent)
        do {
            try await download(url, to: downloads)
            NSWorkspace.shared.open(downloads)
            return nil
        } catch {
            return "下载失败：\(error.localizedDescription)"
        }
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
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