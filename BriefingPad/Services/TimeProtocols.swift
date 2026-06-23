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

final class RealScheduler: Scheduler, @unchecked Sendable {
    private var task: Task<Void, Never>?
    private let lock = NSLock()

    func schedule(after duration: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                action()
            }
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = nil
    }
}
