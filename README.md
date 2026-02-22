# TaskBag

<p align="center">
  <img src="assets/taskbag-logo-full.svg" alt="TaskBag — Async Task Manager" width="400">
</p>

<p align="center">
  <a href="https://github.com/kiarashvosough1999/TaskBag/actions/workflows/swift.yml">
    <img src="https://github.com/kiarashvosough1999/TaskBag/actions/workflows/swift.yml/badge.svg" alt="Swift build and test">
  </a>
  <img src="https://img.shields.io/badge/Swift-6.1-orange?style=flat-square" alt="Swift 6.1">
  <img src="https://img.shields.io/badge/Platforms-macOS_iOS-green?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square" alt="SPM">
  <a href="https://www.linkedin.com/in/kiarashvosough/">
    <img src="https://img.shields.io/badge/LinkedIn-KiarashVosough-blue?style=flat-square" alt="LinkedIn">
  </a>
</p>

A small Swift library for managing async tasks: a simple **TaskBag** that stores tasks in an array (no IDs), and **IdentifiableTaskBag** that runs at most one task per ID. Call **TaskBag.cancel()** or deinit to cancel all tasks.

## Features

- **TaskBag** — Add tasks with `addTask(operation:)` or `add(_:)`. No IDs; no per-task removal. Call `cancel()` to cancel all tasks, or they are cancelled on deinit.
- **IdentifiableTaskBag** — Key tasks by any `Hashable` & `Sendable` type (e.g. `String`, enum). At most one task per ID; duplicate IDs are ignored. Tasks are removed when they complete.
- **Cancellation** — TaskBag: `cancel()` cancels all; deinit cancels all. IdentifiableTaskBag: `cancel(id:)` cancels one task by ID; deinit cancels all.
- **No strong cycles from the bag** — IdentifiableTaskBag’s internal task holds a weak reference to the bag so the bag can deallocate. You must still use `[weak self]` in your closures so the *owner* of the bag can deallocate (see [Cancellation and retain cycles](#cancellation-and-retain-cycles)).

## Requirements

| Platform | Minimum Swift Version | Installation | Status |
| --- | --- | --- | --- |
| iOS 13.0+ | 6.1 | [SPM](#swift-package-manager) | Tested |
| macOS 10.15+ | 6.1 | [SPM](#swift-package-manager) | Tested |

## Installation

### Swift Package Manager

Add TaskBag to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kiarashvosough1999/TaskBag.git", from: "1.0.0"),
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

bag.addTask(id: "refresh") { await doRefresh() }
bag.addTask(id: "refresh") { await doRefresh() }  // ignored
bag.addTask(id: "sync") { await doSync() }        // runs
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

bag.addTask(id: .refresh) { await refreshData() }
bag.addTask(id: .sync) { await syncWithServer() }
```

### Typical pattern: one bag per owner

Keep a bag alongside the object that starts the work. When that object is deallocated, the bag’s `deinit` cancels all its tasks. **Use `[weak self]` in your closures** so the owner can deallocate (see [Cancellation and retain cycles](#cancellation-and-retain-cycles) below).

```swift
final class DataLoader {
    private let bag = IdentifiableTaskBag<String>()

    func loadResource(id: String) {
        bag.addTask(id: id) { [weak self] in
            await self?.fetch(id)
        }
    }
}
```

## Cancellation and retain cycles

TaskBag cancels tasks when you call `cancel()` / `cancel(id:)` or when the bag is deallocated. **If the owner of the bag never deallocates, the bag never gets deinit, and your tasks are never cancelled by the bag.** That can happen when tasks capture the owner strongly.

Swift `Task` (and the closures you pass to `addTask` / `addTask`) **strongly capture** whatever they reference. So if an object holds a TaskBag and adds work that uses `self`, you get a retain cycle:

- **Owner** → holds **TaskBag** → holds **tasks** → each task’s closure captures **Owner** → Owner is never released.

So the holder of the TaskBag can **fail to deallocate** and create a **strong reference cycle** if the stored tasks capture the holder (e.g. `self`) strongly. Long-running or never-completing work (e.g. `for await` over an infinite stream) makes this permanent: the task never finishes, so the cycle never breaks.

**How to avoid it:**

1. **Use `[weak self]`** in closures you pass to `addTask`, and in any `Task { ... }` you pass to `stored(in:)`:
  ```swift
   // ✅ Owner can deallocate; bag’s deinit will cancel tasks
   bag.addTask { [weak self] in await self?.refresh() }
   bag.addTask(id: "x") { [weak self] in await self?.sync() }
   Task { [weak self] in await self?.work() }.stored(in: bag)
  ```
2. **Don’t** rely only on the bag’s deinit if your closures capture `self` strongly:
  ```swift
   // ❌ Retain cycle: owner → bag → task → owner
   bag.addTask { await self.refresh() }
  ```
3. For **long-lived or infinite work** (e.g. `for await value in stream { ... }`), the same rules apply: the task may never complete, so without `[weak self]` the owner and the bag stay alive forever. Explicitly capture only what you need (e.g. the stream) and use weak references for the owner. See [“Using Async For/Await? You’re Probably Doing It Wrong”](https://medium.com/the-swift-cooperative/using-async-for-await-youre-probably-doing-it-wrong-88b66fbb0e84) for the broader async/await and `for await` pitfalls.
4. **Check for task cancellation** in long-running work. When the bag cancels a task (via `cancel()`, `cancel(id:)`, or deinit), the task is marked cancelled but your code must actually stop. Use `Task.isCancelled` or `Task.checkCancellation()` (wrap in `do`/`catch` since `addTask` takes non-throwing closures) so the task exits when cancelled:
  ```swift
   bag.addTask { [weak self] in
       while !Task.isCancelled {
           await self?.doWork()
           try? await Task.sleep(nanoseconds: 1_000_000_000)
       }
   }
   // or, using checkCancellation (do/catch because the closure is non-throwing):
   bag.addTask {
       do {
           try Task.checkCancellation()
           await doLongWork()
       } catch {
           // exit when cancelled
       }
   }
  ```
5. **In a `for await` loop, check `self` for non-null and check for cancellation inside the loop.** With `[weak self]`, use `guard let self else { break }` so that when the owner is deallocated the loop exits, and you get a non-optional `self` for async calls (e.g. `await self.handle(value)`). Also check `Task.isCancelled` (or use `Task.checkCancellation()` in a `do`/`catch`) so the loop exits when the bag cancels the task:
  ```swift
   bag.addTask { [weak self, stream] in
       for await value in stream {
           guard let self else { break }
           if Task.isCancelled { break }
           await self.handle(value)
       }
   }
  ```

**Summary:** TaskBag does not retain your type; the **tasks** you put in it do. Use `[weak self]` (or equivalent) in those tasks so the owner can deallocate and the bag’s `deinit` can run and cancel the tasks. In long-running or `for await` work, check for cancellation and check `self` inside the loop so the task can stop and the loop can exit when the owner is gone.

## API

### TaskBag

No IDs; no per-task removal. Tasks stay in the bag until `cancel()` or deinit.


| Method | Description |
| ------ | ----------- |
| `init()` | Creates an empty task bag. |
| `cancel()` | Cancels all tasks in the bag and clears the bag. |
| `addTask(priority:operation:)` | Adds a task that runs the operation. Optional `priority: TaskPriority?`. Stays in the bag until `cancel()` or deinit. |
| `addDetachedTask(priority:operation:)` | Adds a detached task (not bound to current actor). Optional `priority`. Stays in the bag until `cancel()` or deinit. |
| `add(_ task: Task<Void, Never>)` | Stores an existing task in the bag. Stays in the bag until `cancel()` or deinit. |


### IdentifiableTaskBag


| Method | Description |
| ------ | ----------- |
| `init()` | Creates an empty identifiable task bag. |
| `cancel(id: K)` | Cancels the task for the given ID (if any) and removes it from the bag. |
| `addTask(id:priority:operation:)` | Adds a task under `id` that runs the operation. Optional `priority: TaskPriority?`. If a task for `id` exists, no-op. Removed when the operation finishes. |
| `addDetachedTask(id:priority:operation:)` | Adds a detached task under `id` (not bound to current actor). Optional `priority`. Same semantics as `addTask(id:operation:)`. |
| `add(_ task: Task<Void, Never>, id: K)` | Stores an existing task under `id`. If that ID already has a task, no-op. Cancelled on deinit (not removed when it completes). |


**Generic constraint:** `K: Hashable & Sendable` (e.g. `String`, enums with `Sendable` raw value).

### Task extension


| Method                                           | Description                                                                               |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `task.stored(in: TaskBag)`                       | Stores this task in the bag. The task will be cancelled when the bag is deallocated.      |
| `task.stored(in: IdentifiableTaskBag<K>, id: K)` | Stores this task in the identifiable bag under `id`. No-op if that ID already has a task. |


## Thread safety

Both types use an internal `NSLock` to protect their storage. All methods (`addTask`, `addDetachedTask`, `add`, `cancel`, `cancel(id:)`, and deinit) take the lock for the duration of any read or write. **The bags are thread-safe**: you can call them from multiple threads or tasks concurrently without additional synchronization.

## Running tests

```bash
swift test
```

## License

See the [LICENSE](LICENSE) file in this repository.
