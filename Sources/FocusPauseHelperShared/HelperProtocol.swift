import Foundation

@objc public protocol HelperProtocol {
    func ping(_ token: String, withReply reply: @escaping (Bool, String) -> Void)
    func heartbeat(_ token: String, bundlePath: String)
    func applyHosts(
        _ token: String,
        domains: [String],
        withReply reply: @escaping (Bool, String) -> Void
    )
    func clearHosts(
        _ token: String,
        withReply reply: @escaping (Bool, String) -> Void
    )
    func setDNSServers(
        _ token: String,
        service: String,
        servers: [String],
        withReply reply: @escaping (Bool, String) -> Void
    )
}
