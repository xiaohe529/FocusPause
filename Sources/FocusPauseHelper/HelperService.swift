import Darwin
import Foundation
import FocusPauseHelperShared

final class HelperServiceDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private static let hostsPath = "/private/etc/hosts"
    private static let markerBegin = "# FocusPause BEGIN"
    private static let markerEnd = "# FocusPause END"
    private static let hostsStateQueue = DispatchQueue(label: "com.focuspause.helper.hosts", qos: .userInitiated)

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard newConnection.processIdentifier > 0 else { return false }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func ping(_ token: String, withReply reply: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }
            reply(true, "FocusPauseHelper v1.1")
        }
    }

    func applyHosts(
        _ token: String,
        domains: [String],
        withReply reply: @escaping (Bool, String) -> Void
    ) {
        Self.hostsStateQueue.async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }

            var normalized: [String] = []
            for rawDomain in domains {
                guard let domain = DomainNormalizer.normalize(rawDomain) else {
                    reply(false, "rejected: invalid domain")
                    return
                }
                if !normalized.contains(domain) { normalized.append(domain) }
            }
            guard !normalized.isEmpty else {
                reply(false, "rejected: no domains")
                return
            }

            let content: String
            do {
                content = try String(contentsOfFile: Self.hostsPath, encoding: .utf8)
            } catch {
                reply(false, "unable to read hosts: \(error.localizedDescription)")
                return
            }

            var lines = Self.removeFocusPauseSections(from: content)
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append(Self.markerBegin)
            for domain in normalized {
                lines.append("127.0.0.1 \(domain)")
                lines.append("127.0.0.1 www.\(domain)")
                lines.append("::1 \(domain)")
                lines.append("::1 www.\(domain)")
            }
            lines.append(Self.markerEnd)

            do {
                try Self.writeHostsAtomically(lines.joined(separator: "\n"))
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
        Self.hostsStateQueue.async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }

            let content: String
            do {
                content = try String(contentsOfFile: Self.hostsPath, encoding: .utf8)
            } catch {
                reply(false, "unable to read hosts: \(error.localizedDescription)")
                return
            }

            let lines = Self.removeFocusPauseSections(from: content)
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
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.tokenIsValid(token) else {
                reply(false, "unauthorized")
                return
            }
            guard Self.serviceNameIsValid(service) else {
                reply(false, "rejected: invalid network service")
                return
            }
            guard !servers.isEmpty, servers.allSatisfy(Self.serverValueIsValid) else {
                reply(false, "rejected: invalid DNS servers")
                return
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

    private static func serviceNameIsValid(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 256
            && !value.hasPrefix("-")
            && !value.contains(where: { $0.isNewline || $0.unicodeScalars.contains { $0.value == 0 || $0.properties.isDefaultIgnorableCodePoint } })
    }

    private static func serverValueIsValid(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "Empty" { return true }
        guard !value.isEmpty, value == raw, !value.contains(where: { $0.isNewline || $0 == "\0" }) else {
            return false
        }

        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1
                || inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
    }

    // MARK: - Hosts and system utilities

    private static func removeFocusPauseSections(from content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var removing = false
        var sawBegin = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !removing, trimmed == markerBegin {
                removing = true
                sawBegin = true
                continue
            }
            if removing {
                if trimmed == markerEnd {
                    removing = false
                }
                continue
            }
            if !sawBegin, trimmed == markerEnd {
                // Remove a malformed trailing marker if it exists without a begin marker.
                continue
            }
            result.append(line)
        }

        if removing {
            // A missing end marker must not leak the partial FocusPause section.
            return result
        }
        return result
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
            hostsPath.withCString { destination in
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
