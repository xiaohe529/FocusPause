import Foundation

@objc public protocol HelperProtocol {
    func executeCommand(_ command: String, withReply reply: @escaping (Bool, String) -> Void)
    func ping(_ dummy: String, withReply reply: @escaping (Bool, String) -> Void)
    func verifyToken(_ token: String, withReply reply: @escaping (Bool) -> Void)
}