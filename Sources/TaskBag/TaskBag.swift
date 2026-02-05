// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

public final class TaskBag<K>: @unchecked Sendable where K: Hashable, K: Sendable {

    private var tasks: [K: Task<Void, Never>] = [:]
    private let lock = NSLock()

    public init() {}

    deinit {
        lock.lock()
        let tasks = self.tasks.values
        lock.unlock()

        tasks.forEach { $0.cancel() }
    }

    public func startTask(
        id: K,
        operation: @Sendable @escaping () async -> Void
    ) {
        lock.lock()
        guard tasks[id] == nil else {
            lock.unlock()
            return
        }

        tasks[id] = Task { [weak self] in
            await operation()
            self?.removeTask(id)
        }
        lock.unlock()
    }

    private func removeTask(_ id: K) {
        lock.lock()
        tasks[id] = nil
        lock.unlock()
    }
}
