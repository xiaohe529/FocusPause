import Darwin
import Foundation
import FocusPauseHelperShared

final class HelperServiceDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private static let hostsStateQueue = DispatchQueue(label: "com.focuspause.helper.hosts", qos: .userInitiated)
    private static let stateQueue = DispatchQueue(label: "com.focuspause.helper.state", qos: .utility)
    private static let orphanMonitorQueue = DispatchQueue(label: "com.focuspause.helper.orphan", qos: .utility)
    private static let statePath = "/Library/Application Support/FocusPause/helper-state.json"
    private static let heartbeatPath = "/Library/Application Support/FocusPause/app.heartbeat"
    nonisolated(unsafe) private static var orphanMonitorStarted = false
    private static let orphanMonitorLock = NSLock()

    private struct PersistentState: Codable {
        var dnsBackups: [String: [String]] = [:]
        var appBundlePath: String?
        var lastHeartbeatAt: Date?
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard newConnection.processIdentifier > 0 else { return false }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    override init() {
        super.init()
        Self.startOrphanMonitorIfNeeded()
    }

    func ping(_ token: String, withReply reply: @escaping (Bool, String) -> Void) {
        nonisolated(unsafe) let reply = reply
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }
            reply(true, "FocusPauseHelper v1.2")
        }
    }

    func heartbeat(_ token: String, bundlePath: String) {
        DispatchQueue.global(qos: .utility).async {
            guard Self.tokenIsValid(token),
                  bundlePath.hasSuffix(".app") else {
                return
            }
            Self.stateQueue.sync {
                var state = Self.readState()
                state.appBundlePath = bundlePath
                state.lastHeartbeatAt = Date()
                Self.writeState(state)
            }
        }
    }

    func applyHosts(
        _ token: String,
        domains: [String],
        withReply reply: @escaping (Bool, String) -> Void
    ) {
        nonisolated(unsafe) let reply = reply
        Self.hostsStateQueue.async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }

            let content: String
            do {
                content = try String(contentsOfFile: HelperConstants.hostsPath, encoding: .utf8)
            } catch {
                reply(false, "unable to read hosts: \(error.localizedDescription)")
                return
            }

            guard let content = HelperValidation.makeHostsContent(existing: content, domains: domains) else {
                reply(false, "rejected: invalid domains")
                return
            }

            do {
                try Self.writeHostsAtomically(content)
            } catch {
                reply(false, "unable to write hosts: \(error.localizedDescription)")
                return
            }

            Self.flushDNSCache()
            reply(true, "hosts updated")
        }
    }

    func clearHosts(
        _ token: String,
        withReply reply: @escaping (Bool, String) -> Void
    ) {
        nonisolated(unsafe) let reply = reply
        Self.hostsStateQueue.async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }

            let content: String
            do {
                content = try String(contentsOfFile: HelperConstants.hostsPath, encoding: .utf8)
            } catch {
                reply(false, "unable to read hosts: \(error.localizedDescription)")
                return
            }

            let lines = HelperValidation.removeFocusPauseSections(from: content)
            do {
                try Self.writeHostsAtomically(lines.joined(separator: "\n"))
            } catch {
                reply(false, "unable to write hosts: \(error.localizedDescription)")
                return
            }

            Self.flushDNSCache()
            reply(true, "hosts cleared")
        }
    }

    func setDNSServers(
        _ token: String,
        service: String,
        servers: [String],
        withReply reply: @escaping (Bool, String) -> Void
    ) {
        nonisolated(unsafe) let reply = reply
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }
            guard HelperValidation.serviceNameIsValid(service) else {
                reply(false, "rejected: invalid network service")
                return
            }
            guard !servers.isEmpty, servers.allSatisfy(HelperValidation.serverValueIsValid) else {
                reply(false, "rejected: invalid DNS servers")
                return
            }

            if servers == ["127.0.0.1"] {
                let hasBackup = Self.stateQueue.sync {
                    Self.readState().dnsBackups[service]
                }
                if hasBackup == nil {
                    let currentServers = Self.getCurrentDNSServers(service: service)
                    let originalServers = currentServers.filter { $0 != "127.0.0.1" }
                    Self.stateQueue.sync {
                        var state = Self.readState()
                        state.dnsBackups[service] = originalServers
                        Self.writeState(state)
                    }
                }
            } else {
                Self.stateQueue.sync {
                    var state = Self.readState()
                    state.dnsBackups.removeValue(forKey: service)
                    Self.writeState(state)
                }
            }

            let arguments = ["-setdnsservers", service] + servers
            let result = Self.runTool("/usr/sbin/networksetup", arguments: arguments)
            guard result.status == 0 else {
                reply(false, result.output)
                return
            }

            Self.flushDNSCache()
            reply(true, result.output)
        }
    }

    // MARK: - Persistent helper state

    private static func readState() -> PersistentState {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else {
            return PersistentState()
        }
        let decoder = JSONDecoder()
        // Keep this in sync with writeState(_:), which uses ISO-8601 dates.
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistentState.self, from: data) else {
            return PersistentState()
        }
        return state
    }

    private static func writeState(_ state: PersistentState) {
        do {
            let directory = (statePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                ofItemAtPath: statePath
            )
        } catch {
            NSLog("FocusPauseHelper state write failed: \(error.localizedDescription)")
        }
    }

    private static func getCurrentDNSServers(service: String) -> [String] {
        let result = runTool("/usr/sbin/networksetup", arguments: ["-getdnsservers", service])
        guard result.status == 0 else { return [] }
        if result.output.contains("There aren't any DNS") { return [] }
        return result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func startOrphanMonitorIfNeeded() {
        orphanMonitorLock.lock()
        defer { orphanMonitorLock.unlock() }
        guard !orphanMonitorStarted else { return }
        orphanMonitorStarted = true

        orphanMonitorQueue.async {
            while true {
                checkOrphanedApp()
                Thread.sleep(forTimeInterval: 5 * 60)
            }
        }
    }

    private static func checkOrphanedApp() {
        let state = readState()
        guard let bundlePath = state.appBundlePath,
              let lastHeartbeatAt = state.lastHeartbeatAt else { return }

        // Main app must be gone long enough, and its bundle must be missing.
        guard Date().timeIntervalSince(lastHeartbeatAt) >= 10 * 60,
              !FileManager.default.fileExists(atPath: bundlePath),
              runTool("/usr/bin/pgrep", arguments: ["-x", "FocusPause"]).status != 0 else {
            return
        }

        NSLog("FocusPauseHelper orphaned app detected; cleaning blocking state")
        let hostsCleared = clearHostsUnauthenticated()
        let dnsRestored = restoreDNSForOrphanCleanup(state: state)

        guard hostsCleared, dnsRestored else {
            NSLog("FocusPauseHelper orphan cleanup incomplete; will retry")
            return
        }

        removeHelperFilesAndStop()
    }

    private static func clearHostsUnauthenticated() -> Bool {
        hostsStateQueue.sync {
            do {
                let content = try String(contentsOfFile: HelperConstants.hostsPath, encoding: .utf8)
                let lines = HelperValidation.removeFocusPauseSections(from: content)
                try writeHostsAtomically(lines.joined(separator: "\n"))
                flushDNSCache()
                return true
            } catch {
                NSLog("FocusPauseHelper orphan hosts cleanup failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    private static func restoreDNSForOrphanCleanup(state: PersistentState) -> Bool {
        var succeeded = true

        for (service, servers) in state.dnsBackups {
            let restored = servers.isEmpty ? ["Empty"] : servers
            let result = runTool("/usr/sbin/networksetup", arguments: ["-setdnsservers", service] + restored)
            if result.status != 0 {
                succeeded = false
                NSLog("FocusPauseHelper DNS restore failed for \(service): \(result.output)")
            }
        }

        // Fallback: reset any service still pointed at FocusPause's blocking DNS.
        let listing = runTool("/usr/sbin/networksetup", arguments: ["-listallnetworkservices"])
        guard listing.status == 0 else { return false }
        let services = listing.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty && !$0.contains("An asterisk") && !$0.contains("(*) denotes")
            }

        for service in services {
            let current = getCurrentDNSServers(service: service)
            if current == ["127.0.0.1"] {
                let result = runTool("/usr/sbin/networksetup", arguments: ["-setdnsservers", service, "Empty"])
                if result.status != 0 {
                    succeeded = false
                    NSLog("FocusPauseHelper DNS fallback restore failed for \(service): \(result.output)")
                }
            }
        }
        flushDNSCache()
        return succeeded
    }

    private static func removeHelperFilesAndStop() {
        try? FileManager.default.removeItem(atPath: HelperConstants.tokenPath)
        try? FileManager.default.removeItem(atPath: HelperConstants.installedBinPath)
        try? FileManager.default.removeItem(atPath: HelperConstants.daemonPlistPath)
        try? FileManager.default.removeItem(atPath: statePath)
        try? FileManager.default.removeItem(atPath: heartbeatPath)

        let command = "sleep 0.2; /bin/launchctl bootout system \(HelperConstants.daemonPlistPath) >/dev/null 2>&1 || true"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
    }

    // MARK: - Security

    private static func tokenIsValid(_ token: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HelperConstants.tokenPath)),
              let stored = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty, !token.isEmpty else {
            return false
        }

        let supplied = Array(token.utf8)
        let expected = Array(stored.utf8)
        var diff: UInt8 = supplied.count == expected.count ? 0 : 1
        for index in 0..<min(supplied.count, expected.count) {
            diff |= supplied[index] ^ expected[index]
        }
        return diff == 0
    }

    private static func writeHostsAtomically(_ content: String) throws {
        let normalizedContent = content.hasSuffix("\n") ? content : content + "\n"
        let temporaryPath = "/private/etc/.hosts.focuspause.tmp"
        try? FileManager.default.removeItem(atPath: temporaryPath)

        guard FileManager.default.createFile(
            atPath: temporaryPath,
            contents: Data(normalizedContent.utf8),
            attributes: [
                .posixPermissions: 0o644,
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0,
            ]
        ) else {
            throw NSError(domain: "FocusPauseHelper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "unable to create temporary hosts file"
            ])
        }

        let renameResult = temporaryPath.withCString { temporary in
            HelperConstants.hostsPath.withCString { destination in
                rename(temporary, destination)
            }
        }
        guard renameResult == 0 else {
            let code = errno
            try? FileManager.default.removeItem(atPath: temporaryPath)
            throw NSError(domain: "FocusPauseHelper", code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(code))
            ])
        }
    }

    private static func flushDNSCache() {
        _ = runTool("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        _ = runTool("/usr/bin/killall", arguments: ["mDNSResponder"])
    }

    private static func runTool(_ executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
