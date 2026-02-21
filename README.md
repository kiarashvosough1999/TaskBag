# TaskBag

<p align="center">
  <img src="assets/taskbag-logo.svg" alt="TaskBag logo" width="240">
</p>

A small Swift library for managing async tasks: a simple **TaskBag** that stores tasks in an array (no IDs), and **IdentifiableTaskBag** that runs at most one task per ID. Call **TaskBag.cancel()** or deinit to cancel all tasks.

## Features

- **TaskBag** — Add tasks with `addTask(operation:)` or `add(_:)`. No IDs; no per-task removal. Call `cancel()` to cancel all tasks, or they are cancelled on deinit.
- **IdentifiableTaskBag** — Key tasks by any `Hashable` & `Sendable` type (e.g. `String`, enum). At most one task per ID; duplicate IDs are ignored. Tasks are removed when they complete.
- **Cancellation** — TaskBag: `cancel()` cancels all; deinit cancels all. IdentifiableTaskBag: deinit cancels all.
- **No strong cycles** — IdentifiableTaskBag tasks hold a weak reference so the bag can be released when you're done.

## Requirements

- Swift 6.2+
- macOS 10.15+ / iOS 13+

## Installation

### Swift Package Manager

Add TaskBag to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/TaskBag.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["TaskBag"]
    ),
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Usage

### TaskBag (unkeyed)

Add tasks with no ID; they stay in the bag until you call `cancel()` or the bag is deallocated.

```swift
import TaskBag

let bag = TaskBag()

bag.addTask { await doRefresh() }
bag.addTask { await doSync() }
// Or store an existing task:
Task { await doRefresh() }.stored(in: bag)
// Cancel all when done:
bag.cancel()
```

### IdentifiableTaskBag (keyed by ID)

At most one task per ID; duplicate IDs are ignored until the current task finishes.

```swift
import TaskBag

let bag = IdentifiableTaskBag<String>()

bag.startTask(id: "refresh") { await doRefresh() }
bag.startTask(id: "refresh") { await doRefresh() }  // ignored
bag.startTask(id: "sync") { await doSync() }        // runs
// Or store an existing task under an ID:
Task { await doSync() }.stored(in: bag, id: "sync")
```

### IdentifiableTaskBag with enum IDs

```swift
enum WorkerID: String, Sendable {
    case refresh
    case sync
    case upload
}

let bag = IdentifiableTaskBag<WorkerID>()

bag.startTask(id: .refresh) { await refreshData() }
bag.startTask(id: .sync) { await syncWithServer() }
```

### Typical pattern: one bag per owner

Keep a bag alongside the object that starts the work. When that object is deallocated, the bag’s `deinit` cancels all its tasks.

```swift
final class DataLoader {
    private let bag = IdentifiableTaskBag<String>()

    func loadResource(id: String) {
        bag.startTask(id: id) { await self.fetch(id) }
    }
}
```

## API

### TaskBag

No IDs; no per-task removal. Tasks stay in the bag until `cancel()` or deinit.

| Method | Description |
|--------|-------------|
| `init()` | Creates an empty task bag. |
| `cancel()` | Cancels all tasks in the bag and clears the bag. |
| `addTask(operation: () async -> Void)` | Adds a task that runs the operation. It stays in the bag until `cancel()` or deinit. |
| `add(_ task: Task<Void, Never>)` | Stores an existing task in the bag. It stays in the bag until `cancel()` or deinit. |

### IdentifiableTaskBag&lt;K&gt;

| Method | Description |
|--------|-------------|
| `init()` | Creates an empty identifiable task bag. |
| `startTask(id: K, operation: () async -> Void)` | Starts the async `operation` under `id`. If a task for `id` is already running, this call does nothing. When the operation finishes, the task is removed from the bag. |
| `add(_ task: Task<Void, Never>, id: K)` | Stores an existing task under `id`. If a task for that ID already exists, does nothing. The task will be cancelled on deinit (not removed when it completes). |

**Generic constraint:** `K: Hashable & Sendable` (e.g. `String`, enums with `Sendable` raw value).

### Task extension

| Method | Description |
|--------|-------------|
| `task.stored(in: TaskBag)` | Stores this task in the bag. The task will be cancelled when the bag is deallocated. |
| `task.stored(in: IdentifiableTaskBag<K>, id: K)` | Stores this task in the identifiable bag under `id`. No-op if that ID already has a task. |

## Concurrency note

Both types are intended for use from a single actor or serialized context (e.g. main actor). Concurrent calls from multiple threads may require additional synchronization at the call site for safe use.

## Running tests

```bash
swift test
```

## License

See the [LICENSE](LICENSE) file in this repository.
