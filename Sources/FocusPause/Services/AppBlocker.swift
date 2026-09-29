import AppKit
import Foundation

@MainActor
final class AppBlocker: NSObject {
    /// 预归一化的屏蔽列表：存进去时就把空白 trim 掉，避免每 5 秒的清扫在内层
    /// 循环里对每条规则重复调用 trimmingCharacters。
    ///
    /// 保持 Array 而非 Set：匹配仍用 localizedCaseInsensitiveCompare，它按 Unicode
    /// 规则折叠（ß≡SS、ẞ≡SS、全角Ａ≡A），而 String.lowercased() 不做这些折叠。
    /// 换成 Set + lowercased 会让「Straße」拦不住「STRASSE」，属于真实回退。
    private var blockedApps: [String] = []
    private var isBlockingEnabled = false
    private var sweepTask: Task<Void, Never>?

    func updateBlockedApps(_ names: [String]) {
        blockedApps = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func setBlockingEnabled(_ enabled: Bool) {
        isBlockingEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        stop()
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                await self.sweepOnce()
            }
        }
    }

    func stop() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    /// Run one enforcement pass immediately; used right after enabling blocking so
    /// blocked apps are killed before any follow-up reminder steals focus.
    func enforceNow() async {
        guard isBlockingEnabled else { return }
        await sweepOnce()
    }

    private func sweepOnce() async {
        guard isBlockingEnabled else { return }
        let blocked = blockedApps
        guard !blocked.isEmpty else { return }

        for app in NSWorkspace.shared.runningApplications {
            guard Task.isCancelled == false else { return }
            guard app.activationPolicy == .regular, app.bundleIdentifier != nil else { continue }

            // 名称 / bundle ID / 可执行文件名任一命中即算被屏蔽。
            let bundleFilename = app.bundleURL?
                .lastPathComponent
                .replacingOccurrences(of: ".app", with: "") ?? ""
            let hit = blocked.contains { target in
                app.localizedName?.localizedCaseInsensitiveCompare(target) == .orderedSame
                    || app.bundleIdentifier?.localizedCaseInsensitiveCompare(target) == .orderedSame
                    || bundleFilename.localizedCaseInsensitiveCompare(target) == .orderedSame
            }
            guard hit else { continue }

            let pid = app.processIdentifier
            app.terminate()
            if pid > 0 {
                try? await Task.sleep(for: .seconds(2))
            }

            guard isBlockingEnabled, !Task.isCancelled, pid > 0 else { return }
            let stillRunning = NSWorkspace.shared.runningApplications.contains {
                $0.processIdentifier == pid
            }
            if stillRunning {
                kill(pid, SIGKILL)
            }
            // 继续处理其余被屏蔽的 App，一次清扫全部清掉。
        }
    }
}
