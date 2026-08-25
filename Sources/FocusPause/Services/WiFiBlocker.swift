import Foundation

@MainActor
class WiFiBlocker: ObservableObject {
    @Published var isEnabled = false
    @Published var isProcessing = false

    private static var serviceName: String {
        return _cachedServiceName
    }
    private static var _cachedServiceName: String = {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("Wi-Fi") || trimmed.contains("WiFi") || trimmed.contains("AirPort") {
                    return trimmed
                }
            }
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.contains("An asterisk") && !trimmed.contains("(*) denotes") {
                    return trimmed
                }
            }
            return "Wi-Fi"
        } catch {
            return "Wi-Fi"
        }
    }()

    private static var backupDir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusPause")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static var dnsBackupPath: String {
        backupDir.appendingPathComponent("original_dns.txt").path
    }

    // MARK: - IP validation
    private static func isValidIP(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let parts = trimmed.split(separator: ".")
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else { return false }
        }
        return true
    }

    // MARK: - Public methods
    func checkStatusQuiet() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getdnsservers", Self.serviceName]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains("127.0.0.1") {
                isEnabled = true
                AppState.shared.wifiDisabled = true
            } else {
                isEnabled = false
                AppState.shared.wifiDisabled = false
            }
        } catch {
            // Silently fail
        }
    }

    func toggle() async {
        isProcessing = true
        do {
            if isEnabled {
                FocusLogger.info("WiFiBlocker: restoring DNS")
                try await restoreDNS()
                isEnabled = false
                AppState.shared.wifiDisabled = false
            } else {
                FocusLogger.info("WiFiBlocker: blocking DNS (setting 127.0.0.1)")
                try await blockDNS()
                isEnabled = true
                AppState.shared.wifiDisabled = true
            }
        } catch {
            FocusLogger.error("WiFiBlocker toggle failed: \(error.localizedDescription)")
            AppState.shared.lastError = "网络控制操作失败：\(error.localizedDescription)"
        }
        isProcessing = false
    }

    // MARK: - Block: set DNS to 127.0.0.1
    private func blockDNS() async throws {
        // Delete any stale backup file first
        try? FileManager.default.removeItem(atPath: Self.dnsBackupPath)

        let current = await getCurrentDNS()
        // Only backup if there are valid DNS entries that are not already blocked
        let validDNS = current.filter { Self.isValidIP($0) && $0 != "127.0.0.1" }
        if !validDNS.isEmpty {
            let data = validDNS.joined(separator: "\n")
            try? data.write(toFile: Self.dnsBackupPath, atomically: true, encoding: .utf8)
        }

        let result = await PrivilegedExecutor.run(
            "networksetup -setdnsservers '\(Self.serviceName)' 127.0.0.1")
        if !result.success {
            throw NSError(domain: "WiFiBlocker", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

    // MARK: - Restore: revert to original DNS
    private func restoreDNS() async throws {
        var originalDNS: [String] = []
        if let data = try? String(contentsOfFile: Self.dnsBackupPath, encoding: .utf8) {
            originalDNS = data.components(separatedBy: "\n")
                .filter { !$0.isEmpty && Self.isValidIP($0) }
        }

        let cmd: String
        if originalDNS.isEmpty {
            // No valid backup — set to auto (DHCP)
            cmd = "networksetup -setdnsservers '\(Self.serviceName)' Empty"
        } else {
            let dnsList = originalDNS.joined(separator: " ")
            cmd = "networksetup -setdnsservers '\(Self.serviceName)' \(dnsList)"
        }

        let result = await PrivilegedExecutor.run(cmd)
        if !result.success {
            throw NSError(domain: "WiFiBlocker", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: result.output])
        }
    }

    // MARK: - Helper
    private func getCurrentDNS() async -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getdnsservers", Self.serviceName]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains("There aren't any DNS") {
                return []
            }
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}
