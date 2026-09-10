import Foundation

struct HostsBlocker {
    static let markerBegin = "# FocusPause BEGIN"
    static let markerEnd = "# FocusPause END"
    static let hostsPath = "/etc/hosts"

    static func backupDir() -> URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusPause")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    static func backupOriginalHostsIfNeeded() {
        let backup = backupDir().appendingPathComponent("hosts.backup")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hostsPath)) else { return }
        try? data.write(to: backup, options: .atomic)
    }

    static func apply(domains: [String]) async throws {
        backupOriginalHostsIfNeeded()
        let result = await HelperConnection.shared.applyHosts(domains: domains)
        guard result.success else {
            throw NSError(domain: "HostsBlocker", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

    static func clear() async throws {
        let result = await HelperConnection.shared.clearHosts()
        guard result.success else {
            throw NSError(domain: "HostsBlocker", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }
}
