import Foundation

/// Not @MainActor — timer callbacks run from a background queue.
/// Mirrors ScheduleEngine's pattern. Holds no persistent state; AppState owns
/// the endTimestamp and persists it. This engine only fires onExpire when the
/// deadline passes.
class FocusTimerEngine {
    var onExpire: (() -> Void)?

    private var endTimestamp: Date?
    private var source: DispatchSourceTimer?

    func start(endTimestamp: Date) {
        self.endTimestamp = endTimestamp
        stop()
        checkNow()

        let dq = DispatchQueue(label: "com.focuspause.focustimer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: dq)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkNow()
        }
        timer.resume()
        source = timer
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func checkNow() {
        guard let end = endTimestamp else { return }
        if Date() >= end {
            endTimestamp = nil
            stop()
            onExpire?()
        }
    }
}
