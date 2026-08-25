import Foundation
import FocusPauseHelperShared

final class HelperConnection: @unchecked Sendable {
    static let shared = HelperConnection()

    private let queue = DispatchQueue(label: "com.focuspause.helperconn")
    private var connection: NSXPCConnection?
    private var lastProbeTime: Date = .distantPast
    private var lastProbeResult: Bool = false

    private init() {}

    // MARK: - Public API

    func executePrivileged(_ command: String) async -> (Bool, String) {
        if await probe() {
            if let result = await callHelper(command: command) {
                return result
            }
        }
        return await legacyOSA(command)
    }

    // MARK: - Probe

    func probe() async -> Bool {
        let now = Date()
        let (cached, stale) = queue.sync { () -> (Bool, Bool) in
            let stale = now.timeIntervalSince(lastProbeTime) > 30
            return (lastProbeResult, stale)
        }
        if !stale { return cached }

        let ok = await pingHelper()
        queue.sync {
            lastProbeTime = Date()
            lastProbeResult = ok
        }
        return ok
    }

    /// Force a re-probe, bypassing the cache. Used after install.
    func forceProbe() async -> Bool {
        let ok = await pingHelper()
        queue.sync {
            lastProbeTime = Date()
            lastProbeResult = ok
        }
        return ok
    }

    // MARK: - XPC connection

    private func ensureConnection() -> NSXPCConnection? {
        if let conn = queue.sync(execute: { connection }) {
            return conn
        }
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.queue.sync { self?.connection = nil }
        }
        conn.resume()
        queue.sync { connection = conn }
        return conn
    }

    private func pingHelper() async -> Bool {
        guard let conn = ensureConnection() else {
            FocusLogger.error("HelperConnection: ensureConnection returned nil")
            return false
        }
        return await withCheckedContinuation { cont in
            let proxy = conn.remoteObjectProxyWithErrorHandler { err in
                FocusLogger.error("HelperConnection: XPC error handler called: \(err)")
                cont.resume(returning: false)
            } as! HelperProtocol
            proxy.ping("") { ok, msg in
                if !ok {
                    FocusLogger.error("HelperConnection: ping returned ok=false, msg=\(msg)")
                    cont.resume(returning: false)
                    return
                }
                let token = Self.readToken()
                if token.isEmpty {
                    FocusLogger.error("HelperConnection: readToken returned empty string")
                }
                proxy.verifyToken(token) { tokenOk in
                    if !tokenOk {
                        FocusLogger.error("HelperConnection: verifyToken failed — token mismatch")
                    }
                    cont.resume(returning: tokenOk)
                }
            }
        }
    }

    private func callHelper(command: String) async -> (Bool, String)? {
        guard let conn = ensureConnection() else { return nil }
        return await withCheckedContinuation { cont in
            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: nil)
            } as! HelperProtocol
            proxy.executeCommand(command) { ok, out in
                cont.resume(returning: (ok, out))
            }
        }
    }

    // MARK: - Token

    static func readToken() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HelperConstants.tokenPath)),
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }
        return token
    }

    // MARK: - Fallback

    private func legacyOSA(_ command: String) async -> (Bool, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: Self.legacyOSASync(command))
            }
        }
    }

    private static func legacyOSASync(_ command: String) -> (Bool, String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0,
                    out.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}