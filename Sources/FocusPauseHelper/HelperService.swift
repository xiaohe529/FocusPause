import Foundation
import FocusPauseHelperShared

final class HelperServiceDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        guard pid > 0 else { return false }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func executeCommand(_ command: String,
                        withReply reply: @escaping (Bool, String) -> Void) {
        guard Self.commandLooksSafe(command) else {
            reply(false, "rejected: command shape not allowed")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = ["-c", command]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                reply(proc.terminationStatus == 0,
                      out.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func ping(_ dummy: String, withReply reply: @escaping (Bool, String) -> Void) {
        reply(true, "FocusPauseHelper v1.0")
    }

    func verifyToken(_ token: String, withReply reply: @escaping (Bool) -> Void) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HelperConstants.tokenPath)),
              let stored = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            reply(false); return
        }
        let a = Array(token.utf8)
        let b = Array(stored.utf8)
        var diff: UInt8 = a.count == b.count ? 0 : 1
        for i in 0..<min(a.count, b.count) { diff |= a[i] ^ b[i] }
        reply(diff == 0)
    }

    // MARK: - Security gates

    private static func commandLooksSafe(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Hosts update: only allow cp of our own fixed tmp files to /etc/hosts.
        // Any other source path is rejected — prevents an attacker who somehow
        // obtains the token from clobbering /etc/hosts with arbitrary content.
        let allowedSources = [
            "/Library/Application Support/FocusPause/hosts.apply.tmp",
            "/Library/Application Support/FocusPause/hosts.clear.tmp",
        ]
        // User-home variants (HostsBlocker writes tmp into the user's home dir).
        let allowedSourceSuffixes = [
            "/Application Support/FocusPause/hosts.apply.tmp",
            "/Application Support/FocusPause/hosts.clear.tmp",
        ]
        let hasAllowedSource = allowedSources.contains { trimmed.contains($0) }
            || allowedSourceSuffixes.contains { trimmed.contains($0) }

        if trimmed.hasPrefix("cp ")
            && hasAllowedSource
            && trimmed.contains("'/etc/hosts'")
            && trimmed.contains("dscacheutil -flushcache")
            && trimmed.contains("killall mDNSResponder") {
            return true
        }
        if trimmed.hasPrefix("networksetup -setdnsservers ") { return true }
        return false
    }
}