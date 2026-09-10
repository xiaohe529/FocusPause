import AppKit
import Foundation

@MainActor
final class AppBlocker: NSObject {
    private var blockedApps: [String] = []
    private var isBlockingEnabled = false
    private var sweepTask: Task<Void, Never>?

    func updateBlockedApps(_ names: [String]) {
        blockedApps = names
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

        for app in NSWorkspace.shared.runningApplications {
            guard Task.isCancelled == false else { return }
            guard app.activationPolicy == .regular, app.bundleIdentifier != nil else { continue }

            let name = app.localizedName ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            let bundleFilename = app.bundleURL?
                .lastPathComponent
                .replacingOccurrences(of: ".app", with: "") ?? ""

            for target in blocked {
                let clean = target.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }

                let nameMatch = name.localizedCaseInsensitiveCompare(clean) == .orderedSame
                let bundleMatch = bundleID.localizedCaseInsensitiveCompare(clean) == .orderedSame
                let filenameMatch = bundleFilename.localizedCaseInsensitiveCompare(clean) == .orderedSame
                guard nameMatch || bundleMatch || filenameMatch else { continue }

                let pid = app.processIdentifier
                app.terminate()
                if pid > 0 {
                    try? await Task.sleep(for: .seconds(2))
                }

                guard isBlockingEnabled, !Task.isCancelled, pid > 0 else { break }
                let stillRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.processIdentifier == pid
                }
                if stillRunning {
                    kill(pid, SIGKILL)
                }
                break
            }
        }
    }
}
