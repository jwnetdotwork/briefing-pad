import Foundation

protocol Clock: Sendable {
    var now: Date { get }
}

struct RealClock: Clock {
    var now: Date { Date() }
}

protocol Scheduler: Sendable {
    func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void)
    func cancel()
}

@MainActor
final class RealScheduler: Scheduler {
    private var task: Task<Void, Never>?

    func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                action()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
