# TaskBag

A small Swift library for managing async tasks by ID. Start at most one task per ID, get automatic cleanup when tasks finish, and cancellation when the bag is deallocated.

## Features

- **Keyed tasks** — Run async work keyed by any `Hashable` & `Sendable` type (e.g. `String`, enum).
- **Single task per ID** — Calling `startTask(id:operation:)` with an existing ID is a no-op; no duplicate work.
- **Automatic cleanup** — When a task completes, it is removed from the bag.
- **Cancellation on deinit** — When a `TaskBag` is deallocated, all running tasks are cancelled.
- **No strong cycles** — Tasks hold a weak reference to the bag so the bag can be released when you're done.

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

### Basic example

```swift
import TaskBag

let bag = TaskBag<String>()

// Start a task for ID "refresh"
bag.startTask(id: "refresh") {
    await doRefresh()
}

// Second call with same ID is ignored (task already running)
bag.startTask(id: "refresh") {
    await doRefresh()  // not run
}

// Different IDs run separately
bag.startTask(id: "sync") {
    await doSync()
}
```

### With enum IDs

```swift
enum WorkerID: String, Sendable {
    case refresh
    case sync
    case upload
}

let bag = TaskBag<WorkerID>()

bag.startTask(id: .refresh) {
    await refreshData()
}

bag.startTask(id: .sync) {
    await syncWithServer()
}
```

### Typical pattern: one bag per owner

Keep a `TaskBag` alongside the object that starts the work (e.g. a view model or service). When that object is deallocated, its bag’s `deinit` cancels all its tasks.

```swift
final class DataLoader {
    private let bag = TaskBag<String>()

    func loadResource(id: String) {
        bag.startTask(id: id) {
            await self.fetch(id)
        }
    }
}
```

## API

| Method | Description |
|--------|-------------|
| `init()` | Creates an empty task bag. |
| `startTask(id: K, operation: () async -> Void)` | Starts the async `operation` under `id`. If a task for `id` is already running, this call does nothing. When the operation finishes, the task is removed from the bag. |

**Generic constraint:** `K: Hashable & Sendable` (e.g. `String`, enums with `Sendable` raw value).

## Concurrency note

`TaskBag` is intended for use from a single actor or serialized context (e.g. main actor). Concurrent calls to `startTask(id:operation:)` from multiple threads may require additional synchronization at the call site for safe use.

## Running tests

```bash
swift test
```

## License

See the [LICENSE](LICENSE) file in this repository.
