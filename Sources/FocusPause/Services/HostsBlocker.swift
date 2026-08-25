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
        if let data = try? String(contentsOfFile: hostsPath, encoding: .utf8) {
            try? data.write(to: backup, atomically: true, encoding: .utf8)
        }
    }

    static func apply(domains: [String]) async throws {
        backupOriginalHostsIfNeeded()
        let current = try String(contentsOfFile: hostsPath, encoding: .utf8)
        var lines = current.components(separatedBy: "\n")

        // Remove existing FocusPause section
        if let beginIdx = lines.firstIndex(of: markerBegin),
           let endIdx = lines.firstIndex(of: markerEnd) {
            let range = beginIdx...endIdx
            lines.removeSubrange(range)
        }

        let entries = domains.flatMap { domain -> [String] in
            let clean = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return [
                "127.0.0.1 " + clean,
                "127.0.0.1 www." + clean,
                "::1 " + clean,
                "::1 www." + clean
            ]
        }

        var blockSection = [markerBegin]
        blockSection.append(contentsOf: entries)
        blockSection.append(markerEnd)

        // Remove trailing empty lines
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append(contentsOf: blockSection)
        let newContent = lines.joined(separator: "\n")

        let tmp = backupDir().appendingPathComponent("hosts.apply.tmp")
        try newContent.write(to: tmp, atomically: true, encoding: .utf8)
        let cmd = "cp '" + tmp.path + "' '" + hostsPath + "' && dscacheutil -flushcache; killall mDNSResponder 2>/dev/null; true"
        let result = await PrivilegedExecutor.run(cmd)
        try? FileManager.default.removeItem(at: tmp)

        if !result.success {
            throw NSError(domain: "HostsBlocker", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

    static func clear() async throws {
        let current = try String(contentsOfFile: hostsPath, encoding: .utf8)
        var lines = current.components(separatedBy: "\n")
        if let beginIdx = lines.firstIndex(of: markerBegin),
           let endIdx = lines.firstIndex(of: markerEnd) {
            let range = beginIdx...endIdx
            lines.removeSubrange(range)
        }
        let newContent = lines.joined(separator: "\n")
        let tmp = backupDir().appendingPathComponent("hosts.clear.tmp")
        try newContent.write(to: tmp, atomically: true, encoding: .utf8)
        let cmd = "cp '" + tmp.path + "' '" + hostsPath + "' && dscacheutil -flushcache; killall mDNSResponder 2>/dev/null; true"
        let result = await PrivilegedExecutor.run(cmd)
        try? FileManager.default.removeItem(at: tmp)

        if !result.success {
            throw NSError(domain: "HostsBlocker", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

}