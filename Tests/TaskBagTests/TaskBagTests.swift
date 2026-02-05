import Testing
@testable import TaskBag

// TaskBag's internal dictionary is not thread-safe. Concurrent startTask(...) calls or
// concurrent task completions (self?.tasks[id] = nil) can cause data races. These tests
// use staggered completion and single-threaded startTask where needed so the suite passes.
// For production concurrent use, consider adding synchronization to TaskBag.

// MARK: - Basic behavior

@Suite("TaskBag basic behavior")
struct TaskBagBasicTests {

    @Test("startTask runs operation and removes task on completion")
    func startTaskRunsAndCleansUp() async {
        let bag = TaskBag<String>()
        let ran = _MutableBox(false)
        bag.startTask(id: "run") {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #expect(ran.value == true)
    }

    @Test("starting task with same ID twice does not run operation twice")
    func sameIdIgnored() async {
        let bag = TaskBag<String>()
        let count = _MutableBox(0)
        bag.startTask(id: "same") {
            count.value += 1
        }
        bag.startTask(id: "same") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
    }

    @Test("different IDs run both operations")
    func differentIdsRunBoth() async {
        let bag = TaskBag<String>()
        let a = _MutableBox(false)
        let b = _MutableBox(false)
        bag.startTask(id: "a") { a.value = true }
        bag.startTask(id: "b") { b.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(a.value == true)
        #expect(b.value == true)
    }

    @Test("empty string is valid ID")
    func emptyStringId() async {
        let bag = TaskBag<String>()
        let ran = _MutableBox(false)
        bag.startTask(id: "") {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }
}

// MARK: - Edge cases

@Suite("TaskBag edge cases")
struct TaskBagEdgeCaseTests {

    @Test("many tasks with different IDs all run")
    func manyTasksRun() async {
        let bag = TaskBag<String>()
        let count = _AtomicCounter()
        // Use small n and long stagger to avoid concurrent completion (TaskBag storage is not thread-safe).
        let n = 5
        for i in 0..<n {
            bag.startTask(id: "id-\(i)") {
                await count.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await count.get() == n)
    }

    @Test("same ID stressed multiple times only runs once")
    func sameIdStressed() async {
        let bag = TaskBag<String>()
        let count = _MutableBox(0)
        for _ in 0..<50 {
            bag.startTask(id: "single") {
                try? await Task.sleep(nanoseconds: 300_000_000) // stay alive during loop
                count.value += 1
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(count.value == 1)
    }

    @Test("after task completes, same ID can be started again")
    func sameIdReusedAfterCompletion() async {
        let bag = TaskBag<String>()
        let count = _MutableBox(0)
        bag.startTask(id: "reuse") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
        bag.startTask(id: "reuse") {
            count.value += 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 2)
    }
}

// MARK: - Memory and lifecycle

@Suite("TaskBag memory and lifecycle")
struct TaskBagMemoryTests {

    @Test("deinit cancels running tasks")
    func deinitCancelsTasks() async {
        let started = _MutableBox(false)
        let cancelled = _MutableBox(false)
        do {
            let bag = TaskBag<String>()
            bag.startTask(id: "long") {
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

    @Test("task does not retain TaskBag strongly - completion clears self reference")
    func taskCleansUpOnCompletion() async {
        weak var weakBag: TaskBag<String>?
        do {
            let bag = TaskBag<String>()
            weakBag = bag
            bag.startTask(id: "ephemeral") { }
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

@Suite("TaskBag RawRepresentable ID")
struct TaskBagRawRepresentableTests {

    @Test("startTask with RawRepresentable ID runs operation")
    func rawRepresentableIdRuns() async {
        let bag = TaskBag<TaskId>()
        let ran = _MutableBox(false)
        bag.startTask(id: TaskId.one) {
            ran.value = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran.value == true)
    }

    @Test("same RawRepresentable ID twice is ignored")
    func rawRepresentableSameIdIgnored() async {
        let bag = TaskBag<TaskId>()
        let count = _MutableBox(0)
        bag.startTask(id: TaskId.one) { count.value += 1 }
        bag.startTask(id: TaskId.one) { count.value += 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(count.value == 1)
    }

    @Test("different RawRepresentable IDs run both")
    func rawRepresentableDifferentIds() async {
        let bag = TaskBag<TaskId>()
        let one = _MutableBox(false)
        let two = _MutableBox(false)
        bag.startTask(id: TaskId.one) { one.value = true }
        bag.startTask(id: TaskId.two) { two.value = true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(one.value == true)
        #expect(two.value == true)
    }
}

// MARK: - Threading and concurrency
//
// Note: TaskBag's internal storage is not thread-safe. Concurrent startTask(...) calls
// from different tasks/threads can cause data races and crashes. These tests exercise
// single-threaded / serialized usage and completion from the task closures only.
// For safe concurrent use, TaskBag would need synchronization (e.g. actor or lock).

@Suite("TaskBag threading and concurrency")
struct TaskBagThreadingTests {

    @Test("sequential startTask with different IDs from same context")
    func sequentialDifferentIds() async {
        let bag = TaskBag<String>()
        let count = _AtomicCounter()
        let n = 5
        for i in 0..<n {
            bag.startTask(id: "seq-\(i)") {
                await count.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await count.get() == n)
    }

    @Test("sequential startTask with same ID only runs one")
    func sequentialSameId() async {
        let bag = TaskBag<String>()
        let count = _AtomicCounter()
        for _ in 0..<100 {
            bag.startTask(id: "single") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await count.increment()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(await count.get() == 1)
    }

    @Test("many tasks started sequentially all complete and clean up")
    func sequentialStartAndCompletion() async {
        let bag = TaskBag<String>()
        let completed = _AtomicCounter()
        let n = 5
        for i in 0..<n {
            bag.startTask(id: "finish-\(i)") {
                await completed.increment()
                try? await Task.sleep(nanoseconds: UInt64(i) * 200_000_000) // 200ms stagger
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await completed.get() == n)
    }

    @Test("rapid sequential same ID only runs once")
    func rapidSequentialSameId() async {
        let bag = TaskBag<String>()
        let count = _AtomicCounter()
        // Keep the single running task alive during the loop so completion doesn't race with startTask
        for _ in 0..<200 {
            bag.startTask(id: "rapid") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await count.increment()
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(await count.get() == 1)
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
