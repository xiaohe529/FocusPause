import Foundation

/// Simple file logger. Writes to ~/Library/Logs/FocusPause.log.
/// Not @MainActor — safe to call from any thread. Uses a serial dispatch queue
/// so concurrent writes don't interleave.
enum FocusLogger {
    private static let queue = DispatchQueue(label: "com.focuspause.logger")
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("FocusPause.log")
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(dateFormatter.string(from: Date()))] \(level) \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                // Append; create if missing
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logURL)
                }
            }
            // Rotate: keep log under ~1MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attrs[.size] as? Int, size > 1_000_000 {
                let rolled = logURL.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: rolled)
                try? FileManager.default.moveItem(at: logURL, to: rolled)
            }
        }
    }
}
