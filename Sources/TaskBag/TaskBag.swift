// MIT License
//
// Copyright (c) 2025 TaskBag Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

// MARK: - TaskBag (unkeyed)

/// A bag that stores async tasks in an array. No IDs—add tasks with `addTask(operation:)` or `add(_:)`.
/// Call `cancel()` to cancel all tasks, or they are cancelled when the bag is deallocated.
/// Thread-safe: uses an internal lock; safe to use from multiple threads concurrently.
public final class TaskBag: @unchecked Sendable {

    private var tasks: [Task<Void, Never>] = []
    private let lock: NSLock = NSLock()

    public init() {}

    deinit {
        lock.lock()
        let allTasks: [Task<Void, Never>] = tasks
        tasks = []
        lock.unlock()
        allTasks.forEach { $0.cancel() }
    }

    /// Cancels all tasks stored in the bag and clears the bag.
    public func cancel() {
        lock.lock()
        let allTasks: [Task<Void, Never>] = tasks
        tasks = []
        lock.unlock()
        allTasks.forEach { $0.cancel() }
    }

    /// Adds a new task that runs the given operation. The task stays in the bag until `cancel()` or deinit.
    /// - Parameter priority: Optional task priority; defaults to `nil` (inherited).
    public func addTask(priority: TaskPriority? = nil, operation: sending @escaping @isolated(any) () async -> Void) {
        let task: Task<Void, Never> = Task(priority: priority) { await operation() }
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    /// Adds a new detached task that runs the given operation. The task is not bound to the current actor context.
    /// The task stays in the bag until `cancel()` or deinit.
    /// - Parameter priority: Optional task priority; defaults to `nil` (inherited).
    public func addDetachedTask(priority: TaskPriority? = nil, operation: sending @escaping @isolated(any) () async -> Void) {
        let task: Task<Void, Never> = Task.detached(priority: priority) { await operation() }
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    /// Stores an existing task in the bag. It stays in the bag until `cancel()` or deinit.
    public func add(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }
}

// MARK: - IdentifiableTaskBag (keyed by ID)

/// A bag that runs at most one task per ID. Use `addTask(id:operation:)` to run
/// keyed async work; duplicate IDs are ignored, and tasks are cancelled on deinit.
/// Thread-safe: uses an internal lock; safe to use from multiple threads concurrently.
public final class IdentifiableTaskBag<K>: @unchecked Sendable where K: Hashable, K: Sendable {

    private var tasks: [K: Task<Void, Never>] = [:]
    private let lock: NSLock = NSLock()

    public init() {}

    deinit {
        lock.lock()
        let tasks = self.tasks.values
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    /// Adds a task for the given ID that runs the operation. If a task for this ID is already running, this call does nothing.
    /// When the operation completes, the task is removed from the bag.
    /// - Parameter priority: Optional task priority; defaults to `nil` (inherited).
    public func addTask(
        id: K,
        priority: TaskPriority? = nil,
        operation: sending @escaping @isolated(any) () async -> Void
    ) {
        lock.lock()
        guard tasks[id] == nil else {
            lock.unlock()
            return
        }

        tasks[id] = Task(priority: priority) { [weak self] in
            await operation()
            self?.removeCompletedTask(id)
        }
        lock.unlock()
    }

    /// Adds a detached task for the given ID. The task is not bound to the current actor context.
    /// If a task for this ID is already running, this call does nothing. When the operation completes, the task is removed from the bag.
    /// - Parameter priority: Optional task priority; defaults to `nil` (inherited).
    public func addDetachedTask(
        id: K,
        priority: TaskPriority? = nil,
        operation: sending @escaping @isolated(any) () async -> Void
    ) {
        lock.lock()
        guard tasks[id] == nil else {
            lock.unlock()
            return
        }

        tasks[id] = Task.detached(priority: priority) { [weak self] in
            await operation()
            self?.removeCompletedTask(id)
        }
        lock.unlock()
    }

    /// Stores an existing task in the bag under the given ID. If a task for this ID is already
    /// running, this call does nothing. The stored task will be cancelled when the bag is deallocated.
    /// The task is not removed from the bag when it completes (unlike `addTask(id:operation:)`).
    public func add(_ task: Task<Void, Never>, id: K) {
        lock.lock()
        guard tasks[id] == nil else {
            lock.unlock()
            return
        }
        tasks[id] = task
        lock.unlock()
    }

    /// Cancels the task for the given ID (if any) and removes it from the bag.
    public func cancel(id: K) {
        lock.lock()
        let task: Task<Void, Never>? = tasks[id]
        tasks[id] = nil
        lock.unlock()
        task?.cancel()
    }

    private func removeCompletedTask(_ id: K) {
        lock.lock()
        tasks[id] = nil
        lock.unlock()
    }
}

// MARK: - Task extensions

extension Task where Success == Void, Failure == Never {

    /// Stores this task in the bag. The task will be cancelled when the bag is deallocated.
    public func stored(in bag: TaskBag) {
        bag.add(self)
    }

    /// Stores this task in the identifiable bag under the given ID. If a task for this ID
    /// already exists, this call does nothing. The task will be cancelled when the bag is deallocated.
    public func stored<K>(in bag: IdentifiableTaskBag<K>, id: K) where K: Hashable, K: Sendable {
        bag.add(self, id: id)
    }
}
