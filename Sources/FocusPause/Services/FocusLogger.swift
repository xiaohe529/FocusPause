import Foundation

/// Simple file logger. Writes to ~/Library/Logs/FocusPause.log.
/// Not @MainActor — safe to call from any thread. Uses a serial dispatch queue
/// so concurrent writes don't interleave.
enum FocusLogger {
    private static let queue = DispatchQueue(label: "com.focuspause.logger")
    /// 累计已写字节数。每次写盘都去 stat 文件既慢又会让日志线程和主线程
    /// 争同一个 inode 的元数据；改为在内存里累加，只有估算值超过上限时
    /// 才真正读一次文件确认。
    ///
    /// 放进引用类型持有器而非裸 `static var`，Swift 6 才认它是不可变全局。
    private final class ByteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        /// 累加并返回是否已超过轮转阈值。
        func add(_ bytes: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            count += bytes
            return count > limit
        }

        func reset() {
            lock.lock()
            count = 0
            lock.unlock()
        }
    }

    private static let bytesWritten = ByteCounter(limit: 1_000_000)
    private static let rotationThreshold = 1_000_000

    /// DateFormatter 不是线程安全的，而 write() 会在主线程（AppState）和
    /// helper 回调线程上同时被调用。这里统一加锁，保证同一时刻只有一个格式化。
    private static let formatterLock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func timestamp() -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return dateFormatter.string(from: Date())
    }

    /// 目录只需创建一次，缓存路径即可；原实现每写一行都 mkdir 一次。
    private static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("FocusPause.log")
    }()

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(timestamp())] \(level) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = logURL
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url)
            }

            guard bytesWritten.add(data.count) else { return }
            // 估算值超限后读一次真实大小，避免内存计数与实际文件脱节后不再轮转。
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > rotationThreshold {
                let rolled = url.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: rolled)
                try? FileManager.default.moveItem(at: url, to: rolled)
                bytesWritten.reset()
            }
        }
    }
}
