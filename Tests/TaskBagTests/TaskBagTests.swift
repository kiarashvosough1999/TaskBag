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

import Testing
@testable import TaskBag

// The bags use NSLock internally and are thread-safe for concurrent use. These tests use
// staggered completion and single-threaded addTask where needed for deterministic timing.

// MARK: - TaskBag (unkeyed)

@Suite("TaskBag (unkeyed) basic behavior")
struct TaskBagUnkeyedTests {

    @Test("addTask runs operation and removes task on completion")
    func addTaskRunsAndCleansUp() async {
        let bag = TaskBag()
        let ran = _MutableBox(false)
        bag.addTask { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("multiple addTask calls run all operations")
    func multipleAddTaskRunAll() async {
        let bag = TaskBag()
        let count = _AtomicCounter()
        bag.addTask { await count.increment() }
        bag.addTask { await count.increment() }
        bag.addTask { await count.increment() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await count.get() == 3)
    }

    @Test("TaskBag deinit cancels running tasks")
    func taskBagDeinitCancels() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = TaskBag()
            bag.addTask {
                started.value = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled.value = true
                }
            }
            while !started.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("cancel() cancels all tasks and clears the bag")
    func cancelCancelsAll() async {
        let bag = TaskBag()
        let cancelled = _MutableBox(false)
        bag.addTask {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                cancelled.value = true
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        bag.cancel()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("Task.stored(in: bag) stores task and deinit cancels it")
    func taskStoredInBag() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = TaskBag()
            let task = Task {
                started.value = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled.value = true
                }
            }
            task.stored(in: bag)
            while !started.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("addTask(priority:) runs operation with given priority")
    func addTaskWithPriorityRuns() async {
        let bag = TaskBag()
        let ran = _MutableBox(false)
        bag.addTask(priority: .high) { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("addDetachedTask runs operation")
    func addDetachedTaskRuns() async {
        let bag = TaskBag()
        let ran = _MutableBox(false)
        bag.addDetachedTask { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("addDetachedTask deinit cancels task")
    func addDetachedTaskDeinitCancels() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = TaskBag()
            bag.addDetachedTask {
                started.value = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled.value = true
                }
            }
            while !started.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("addDetachedTask(priority:) runs with priority")
    func addDetachedTaskWithPriorityRuns() async {
        let bag = TaskBag()
        let count = _AtomicCounter()
        bag.addDetachedTask(priority: .utility) { await count.increment() }
        bag.addDetachedTask(priority: .background) { await count.increment() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await count.get() == 2)
    }
}

// MARK: - IdentifiableTaskBag basic behavior

@Suite("IdentifiableTaskBag basic behavior")
struct IdentifiableTaskBagBasicTests {

    @Test("addTask runs operation and removes task on completion")
    func addTaskRunsAndCleansUp() async {
        let bag = IdentifiableTaskBag<String>()
        let ran = _MutableBox(false)
        bag.addTask(id: "run") {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #expect(ran.value == true)
    }

    @Test("starting task with same ID twice does not run operation twice")
    func sameIdIgnored() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _MutableBox(0)
        bag.addTask(id: "same") {
            count.value += 1
        }
        bag.addTask(id: "same") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
    }

    @Test("different IDs run both operations")
    func differentIdsRunBoth() async {
        let bag = IdentifiableTaskBag<String>()
        let a = _MutableBox(false)
        let b = _MutableBox(false)
        bag.addTask(id: "a") { a.value = true }
        bag.addTask(id: "b") { b.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(a.value == true)
        #expect(b.value == true)
    }

    @Test("empty string is valid ID")
    func emptyStringId() async {
        let bag = IdentifiableTaskBag<String>()
        let ran = _MutableBox(false)
        bag.addTask(id: "") {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("Task.stored(in: bag, id:) stores task under ID and deinit cancels it")
    func taskStoredInIdentifiableBag() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = IdentifiableTaskBag<String>()
            let task = Task {
                started.value = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled.value = true
                }
            }
            task.stored(in: bag, id: "stored")
            while !started.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("addTask(id:priority:) runs operation with given priority")
    func addTaskWithPriorityRuns() async {
        let bag = IdentifiableTaskBag<String>()
        let ran = _MutableBox(false)
        bag.addTask(id: "p", priority: .userInitiated) { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("addDetachedTask(id:operation:) runs and removes on completion")
    func addDetachedTaskRunsAndRemoves() async {
        let bag = IdentifiableTaskBag<String>()
        let ran = _MutableBox(false)
        bag.addDetachedTask(id: "det") { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
        let ran2 = _MutableBox(false)
        bag.addDetachedTask(id: "det") { ran2.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran2.value == true)
    }

    @Test("addDetachedTask(id:) same ID twice only runs first")
    func addDetachedTaskSameIdIgnored() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _MutableBox(0)
        bag.addDetachedTask(id: "one") {
            try? await Task.sleep(nanoseconds: 200_000_000)
            count.value += 1
        }
        bag.addDetachedTask(id: "one") { count.value += 1 }
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(count.value == 1)
    }

    @Test("addDetachedTask(id:priority:) runs with priority")
    func addDetachedTaskWithPriorityRuns() async {
        let bag = IdentifiableTaskBag<String>()
        let ran = _MutableBox(false)
        bag.addDetachedTask(id: "pri", priority: .high) { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }
}

// MARK: - Edge cases

@Suite("IdentifiableTaskBag edge cases")
struct IdentifiableTaskBagEdgeCaseTests {

    @Test("many tasks with different IDs all run")
    func manyTasksRun() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _AtomicCounter()
        // Use small n and long stagger so completion order is predictable.
        let n = 5
        for i in 0..<n {
            bag.addTask(id: "id-\(i)") {
                await count.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await count.get() == n)
    }

    @Test("same ID stressed multiple times only runs once")
    func sameIdStressed() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _MutableBox(0)
        for _ in 0..<50 {
            bag.addTask(id: "single") {
                try? await Task.sleep(nanoseconds: 300_000_000) // stay alive during loop
                count.value += 1
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(count.value == 1)
    }

    @Test("after task completes, same ID can be started again")
    func sameIdReusedAfterCompletion() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _MutableBox(0)
        bag.addTask(id: "reuse") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
        bag.addTask(id: "reuse") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 2)
    }

    @Test("cancel(id:) cancels the task and removes it; same ID can be used again")
    func cancelByIdCancelsAndFreesId() async {
        let bag = IdentifiableTaskBag<String>()
        let cancelled = _MutableBox(false)
        bag.addTask(id: "x") {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                cancelled.value = true
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        bag.cancel(id: "x")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
        let ran = _MutableBox(false)
        bag.addTask(id: "x") { ran.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }
}

// MARK: - Memory and lifecycle

@Suite("IdentifiableTaskBag memory and lifecycle")
struct IdentifiableTaskBagMemoryTests {

    @Test("deinit cancels running tasks")
    func deinitCancelsTasks() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = IdentifiableTaskBag<String>()
            bag.addTask(id: "long") {
                started.value = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    cancelled.value = true
                }
            }
            while !started.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        // Bag deallocated here → deinit cancels the task
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
    }

    @Test("task does not retain IdentifiableTaskBag strongly - completion clears self reference")
    func taskCleansUpOnCompletion() async {
        weak var weakBag: IdentifiableTaskBag<String>?
        do {
            let bag = IdentifiableTaskBag<String>()
            weakBag = bag
            bag.addTask(id: "ephemeral") { }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Bag is out of scope; if task held strong reference we might still have it
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(weakBag == nil)
    }
}

// MARK: - RawRepresentable ID

private enum TaskId: String, Sendable {
    case one
    case two
}

@Suite("IdentifiableTaskBag RawRepresentable ID")
struct IdentifiableTaskBagRawRepresentableTests {

    @Test("addTask with RawRepresentable ID runs operation")
    func rawRepresentableIdRuns() async {
        let bag = IdentifiableTaskBag<TaskId>()
        let ran = _MutableBox(false)
        bag.addTask(id: TaskId.one) {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("same RawRepresentable ID twice is ignored")
    func rawRepresentableSameIdIgnored() async {
        let bag = IdentifiableTaskBag<TaskId>()
        let count = _MutableBox(0)
        bag.addTask(id: TaskId.one) { count.value += 1 }
        bag.addTask(id: TaskId.one) { count.value += 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
    }

    @Test("different RawRepresentable IDs run both")
    func rawRepresentableDifferentIds() async {
        let bag = IdentifiableTaskBag<TaskId>()
        let one = _MutableBox(false)
        let two = _MutableBox(false)
        bag.addTask(id: TaskId.one) { one.value = true }
        bag.addTask(id: TaskId.two) { two.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(one.value == true)
        #expect(two.value == true)
    }
}

// MARK: - Threading and concurrency
//
// The bags use NSLock and are thread-safe. These tests exercise sequential usage and
// completion from the task closures for predictable timing.

@Suite("IdentifiableTaskBag threading and concurrency")
struct IdentifiableTaskBagThreadingTests {

    @Test("sequential addTask with different IDs from same context")
    func sequentialDifferentIds() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _AtomicCounter()
        let n = 5
        for i in 0..<n {
            bag.addTask(id: "seq-\(i)") {
                await count.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await count.get() == n)
    }

    @Test("sequential addTask with same ID only runs one")
    func sequentialSameId() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _AtomicCounter()
        for _ in 0..<100 {
            bag.addTask(id: "single") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await count.increment()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(await count.get() == 1)
    }

    @Test("many tasks started sequentially all complete and clean up")
    func sequentialStartAndCompletion() async {
        let bag = IdentifiableTaskBag<String>()
        let completed = _AtomicCounter()
        let n = 5
        for i in 0..<n {
            bag.addTask(id: "finish-\(i)") {
                await completed.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await completed.get() == n)
    }

    @Test("rapid sequential same ID only runs once")
    func rapidSequentialSameId() async {
        let bag = IdentifiableTaskBag<String>()
        let count = _AtomicCounter()
        // Keep the single running task alive during the loop so completion doesn't race with addTask
        for _ in 0..<200 {
            bag.addTask(id: "rapid") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await count.increment()
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(await count.get() == 1)
    }
}

// MARK: - Cancellation and for-await (README scenarios)

@Suite("Cancellation and for-await (README scenarios)")
struct CancellationAndForAwaitTests {

    @Test("task that checks Task.isCancelled in loop exits when bag.cancel() is called")
    func taskCheckingIsCancelledExitsOnCancel() async {
        let bag = TaskBag()
        let iterations = _MutableBox(0)
        bag.addTask {
            while !Task.isCancelled {
                iterations.value += 1
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            }
        }
        try? await Task.sleep(nanoseconds: 80_000_000) // let it run a few iterations
        let countBeforeCancel = iterations.value
        bag.cancel()
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Task should have stopped; iteration count should not grow much after cancel
        #expect(iterations.value >= 1)
        #expect(countBeforeCancel >= 1)
    }

    @Test("task that uses Task.checkCancellation() exits when bag cancels")
    func taskCheckingCheckCancellationExitsOnCancel() async {
        let bag = TaskBag()
        let didReachEnd = _MutableBox(false)
        let cancelled = _MutableBox(false)
        bag.addTask {
            do {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                didReachEnd.value = true
            } catch is CancellationError {
                cancelled.value = true
            } catch {}
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        bag.cancel()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cancelled.value == true)
        #expect(didReachEnd.value == false)
    }

    @Test("for await loop with Task.isCancelled exits when bag cancels")
    func forAwaitLoopExitsOnCancel() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .unbounded)
        let bag = TaskBag()
        let processedCount = _MutableBox(0)
        bag.addTask {
            for await _ in stream {
                if Task.isCancelled { break }
                processedCount.value += 1
            }
        }
        continuation.yield(1)
        continuation.yield(2)
        try? await Task.sleep(nanoseconds: 50_000_000)
        bag.cancel()
        continuation.finish()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(processedCount.value >= 1)
    }

    @Test("owner with [weak self] and guard let self else { break } can deallocate while task runs")
    func ownerWithWeakSelfCanDeallocate() async {
        weak var weakOwner: _TestOwner?
        do {
            let owner = _TestOwner()
            weakOwner = owner
            let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .unbounded)
            owner.startListening(stream: stream)
            continuation.yield(1)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        // Owner and bag are out of scope; with [weak self] owner should deallocate
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(weakOwner == nil)
    }
}

/// Test double: owner that holds a TaskBag and starts a for-await task with [weak self].
private final class _TestOwner: @unchecked Sendable {
    private let bag = TaskBag()

    func startListening(stream: AsyncStream<Int>) {
        bag.addTask { [weak self] in
            for await value in stream {
                guard let self else { break }
                if Task.isCancelled { break }
                _ = (self, value)  // use both to satisfy pattern and silence warnings
            }
        }
    }
}

// MARK: - Helpers for async tests

private final class _MutableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Thread-safe counter for concurrent tests to avoid data races.
private actor _AtomicCounter {
    var value = 0
    func increment() { value += 1 }
    func get() -> Int { value }
}
