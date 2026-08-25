import AppKit
import Foundation

/// Not @MainActor — timer callbacks run from background queue
class AppBlocker: NSObject {
    private var blockedApps: [String] = []
    private var isBlockingEnabled = false
    private var source: DispatchSourceTimer?

    func updateBlockedApps(_ names: [String]) {
        blockedApps = names
    }

    func setBlockingEnabled(_ enabled: Bool) {
        isBlockingEnabled = enabled
        if enabled {
            sweepOnce()
        }
    }

    func start() {
        let dq = DispatchQueue(label: "com.focuspause.appblocker", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: dq)
        timer.schedule(deadline: .now() + 5, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.sweepOnce()
        }
        timer.resume()
        source = timer
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func sweepOnce() {
        guard isBlockingEnabled else { return }
        let blocked = blockedApps
        let enabled = isBlockingEnabled
        guard enabled else { return }

        let running = NSWorkspace.shared.runningApplications
        for app in running {
            // Skip non-app processes: input methods, system helpers, agents
            guard app.activationPolicy == .regular else { continue }
            guard app.bundleIdentifier != nil else { continue }

            let name = app.localizedName ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            let bundleFilename = app.bundleURL?.lastPathComponent.replacingOccurrences(of: ".app", with: "") ?? ""
            for target in blocked {
                let clean = target.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                // Exact match (case-insensitive) on localizedName, bundleIdentifier, or bundle filename.
                // Filename match is needed because loadInstalledApps() returns bundle filenames
                // (e.g. "WeChat") which differ from localizedName ("微信") for many CJK apps.
                let nameMatch = name.localizedCaseInsensitiveCompare(clean) == .orderedSame
                let bundleMatch = bundleID.localizedCaseInsensitiveCompare(clean) == .orderedSame
                let filenameMatch = bundleFilename.localizedCaseInsensitiveCompare(clean) == .orderedSame
                guard nameMatch || bundleMatch || filenameMatch else { continue }
                let pid = app.processIdentifier
                app.terminate()
                sleep(2)
                // Check again — terminate is async and may fail if app ignores it
                if isBlockingEnabled {
                    let stillRunning = NSWorkspace.shared.runningApplications.contains {
                        $0.processIdentifier == pid
                    }
                    if stillRunning {
                        // Force kill by PID — avoids killall's name-collision hazard
                        kill(pid, SIGKILL)
                    }
                }
                break
            }
        }
    }
}
