import Foundation

@MainActor
final class FocusTimerEngine {
    var onExpire: (() -> Void)?

    private var endTimestamp: Date?
    private var timerTask: Task<Void, Never>?

    func start(endTimestamp: Date) {
        self.endTimestamp = endTimestamp
        stop()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.checkNow()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
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
