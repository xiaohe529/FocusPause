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

    func applyHosts(domains: [String]) async -> (success: Bool, output: String) {
        await call { proxy, continuation in
            proxy.applyHosts(Self.readToken(), domains: domains) { ok, output in
                continuation(ok, output)
            }
        }
    }

    func clearHosts() async -> (success: Bool, output: String) {
        await call { proxy, continuation in
            proxy.clearHosts(Self.readToken()) { ok, output in
                continuation(ok, output)
            }
        }
    }

    func setDNSServers(service: String, servers: [String]) async -> (success: Bool, output: String) {
        await call { proxy, continuation in
            proxy.setDNSServers(Self.readToken(), service: service, servers: servers) { ok, output in
                continuation(ok, output)
            }
        }
    }

    // MARK: - Probe

    func probe() async -> Bool {
        let now = Date()
        let (cachedResult, isStale) = queue.sync { () -> (Bool, Bool) in
            (lastProbeResult, now.timeIntervalSince(lastProbeTime) > 30)
        }
        if !isStale { return cachedResult }

        let ok = await pingHelper()
        queue.sync {
            lastProbeTime = Date()
            lastProbeResult = ok
        }
        return ok
    }

    func forceProbe() async -> Bool {
        let ok = await pingHelper()
        queue.sync {
            lastProbeTime = Date()
            lastProbeResult = ok
        }
        return ok
    }

    // MARK: - XPC calls

    private func call(
        _ operation: @escaping @Sendable (HelperProtocol, @escaping @Sendable (Bool, String) -> Void) -> Void
    ) async -> (success: Bool, output: String) {
        guard await probe(), let conn = ensureConnection() else {
            return (false, "FocusPause helper unavailable")
        }

        return await withCheckedContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
                FocusLogger.error("HelperConnection: XPC call failed: \(error)")
                self?.markConnectionInvalid()
                continuation.resume(returning: (false, "FocusPause helper connection failed"))
            } as? HelperProtocol

            guard let proxy else {
                continuation.resume(returning: (false, "FocusPause helper interface unavailable"))
                return
            }

            operation(proxy) { ok, output in
                continuation.resume(returning: (ok, output))
            }
        }
    }

    private func pingHelper() async -> Bool {
        guard let conn = ensureConnection() else {
            FocusLogger.error("HelperConnection: ensureConnection returned nil")
            return false
        }

        return await withCheckedContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
                FocusLogger.error("HelperConnection: XPC probe failed: \(error)")
                self?.markConnectionInvalid()
                continuation.resume(returning: false)
            } as? HelperProtocol

            guard let proxy else {
                continuation.resume(returning: false)
                return
            }

            proxy.ping(Self.readToken()) { ok, message in
                guard ok else {
                    FocusLogger.error("HelperConnection: ping failed: \(message)")
                    continuation.resume(returning: false)
                    return
                }
                guard message == "FocusPauseHelper v1.1" else {
                    FocusLogger.error("HelperConnection: incompatible helper protocol: \(message)")
                    self.markConnectionInvalid()
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: true)
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection? {
        if let existing = queue.sync(execute: { connection }) {
            return existing
        }

        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.queue.async {
                self?.connection = nil
            }
        }
        conn.resume()
        queue.sync { connection = conn }
        return conn
    }

    private func markConnectionInvalid() {
        queue.async {
            self.lastProbeResult = false
            self.lastProbeTime = .distantPast
            self.connection?.invalidate()
            self.connection = nil
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
}
