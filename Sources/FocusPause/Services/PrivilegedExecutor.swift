import Foundation

struct PrivilegedExecutor {
    static func run(_ command: String) async -> (success: Bool, output: String) {
        let r = await HelperConnection.shared.executePrivileged(command)
        return (r.0, r.1)
    }
}