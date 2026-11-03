# Concurrency: promises and pipes

Status: **final proposal, approved by Chinmay; nothing built** (2026-11-02, checked against `f7c0285a`). This consolidates the design Chinmay and Claude reached in the project thread "Redesign concurrency from first principles". It supersedes `single-threaded-runtime.md` (the removal is cancelled and nothing was merged), `shared-single-thread.md`, `shared-lock.md` and `http-server-multicore.md`. Snippets are unchecked. The work ships as one implementation.

## In one paragraph

Every call that can wait starts its work immediately and returns a `Promise[T]`. `wait()` gives the result, and a task pauses only where the word `wait` appears. `promise(fn: ...)` runs your own function this way, on whichever thread the runtime picks; there is no separate worker API. All threads share one heap, and values move between them by pointer, never copied. Many values flow over typed streams (`ReadStream[T]`, `WriteStream[T]`, and an in-memory `pipe[T]`). There are no channels, groups, locks or shared cells. The HTTP server is one `serve` that runs on every core and is built from these pieces.

## Why

- **Concurrency solves three problems.**
  - Waiting on many things: servers, `fetch` fan-out, tests that run a client and a server in one process.
  - Using many cores: CPU-bound handlers scale from 26k to 58k req/s on two threads (`http-server-multicore.md`), and parallel sorts and image work need them too.
  - Bounding what was started: timeouts, Ctrl-C, shutdown.
- **Today eight mechanisms answer these.** They are `TaskGroup[T,In,Out]`, `TaskChannel`, `WorkerGroup`, `ProcessGroup`, `Channel`+`Transport`, `Shared`/`lock`/`Once`, timeouts at two levels, and `contain_faults`.
- **`Shared` exists only because tasks, closures and read-only interface methods had no sound way to reach state they don't own.** The owner rejected it, along with cells and `RefCell`. No use case needs two threads writing one heap.

## Public API

`@std/concurrency/promise.ms`

```manuscript
// Work that has started; its result arrives later.
export opaque type Promise[T]

impl Promise[T]:
    // Waits for the result and moves it out. Errors: the operation's own error; Failed (a fault
    // inside, with its report); Cancelled; Closed (an earlier wait already took the result);
    // Timeout (the work is cancelled) once `timeout` passes.
    fn wait(timeout: Duration? = none) T!
    fn done() Bool
// Dropping an unfinished promise cancels it and waits for it to end. An unused promise is a warning.

export fn promise[U](entry: fn() U!) Promise[U]          // runs entry on a thread the runtime picks; captures are moved or read in place
export fn wait_all[T](promises: List[Promise[T]]) List[T]!   // results in order; the first error cancels the rest
export fn wait_first[T](promises: List[Promise[T]]) T!       // the first result; the rest are cancelled
```

`@std/io/io.ms` (the existing stream interfaces become generic; files, sockets and stdio are `[Bytes]`)

```manuscript
export interface ReadStream[T]:
    var fn read() Promise[T?]          // one step; none at the end
    var fn wait() Waiting[T]           // for item in input.wait(): each step waits, the end included
export interface WriteStream[T]:
    var fn write(value: T) Unit!           // moves value into the stream's buffer and returns at once; never waits; Closed after the reader is gone
    var fn flush() Promise[Unit]           // waits until the buffer is drained: the backpressure point
    fn buffered() Int                      // values or bytes not yet drained, to decide when to flush
// Waiting[T] is an Iterator[T!]. A ReadStream is not an Iterator itself, so every stream loop says wait.
// Both kinds are Closeable: scope end closes them, and close never waits.

export opaque type Pipe[T]             // in memory: any number of writers, one reader, values whole and in order; `capacity` is the level above which a writer's flush waits
impl Pipe[T]:
    fn writer() WriteStream[T]         // a new writing end, like dup on an fd
    var fn reader() ReadStream[T]      // the one reading end; it ends when every writer is closed
export fn pipe[T](capacity: Int) Pipe[T]

export fn json_reader[T: Data](input: ReadStream[Bytes]) ReadStream[T]    // typed view of a byte stream
export fn json_writer[T: Data](output: WriteStream[Bytes]) WriteStream[T]
export fn read_chunk(input: ReadStream[Bytes], max_bytes: Int) Promise[Bytes?]
export fn write_text(output: WriteStream[Bytes], text: String) Unit!
```

Every other waiting call returns a promise: `read(path)`, `write(path, ...)`, `fetch`, `connect`, `sleep`, `exec` and `Listener.accept`.

## Example

```manuscript
fn summarize(urls: List[String], log: ReadStream[Bytes]) Summary!:
    let config = read("config.json")                 // Promise[Bytes], already running
    let pages = urls.map(fn u: fetch(u))             // all in flight together
    let stats = promise(fn: count_words(urls))       // may run on another core

    var errors = 0
    for chunk in log.wait():                         // each step waits
        errors += count_errors(try chunk)

    let settings = try config.wait()
    let bodies = try wait_all(pages)
    let words = try stats.wait(timeout: seconds(5))
    let mirror = try wait_first([fetch(a), fetch(b)])
    return ok(Summary(settings, bodies, words, errors, mirror))
```

## Public rules (the guide states only these)

1. A call that can wait returns a `Promise[T]` that is already running. `wait()` gives `T!` and takes the result once.
2. A task pauses only where `wait` appears. Code between two waits runs without interleaving.
3. `promise(fn: ...)` runs on a thread the runtime picks and stays there. A CPU-heavy promise delays the promises sharing its thread until it waits. A promise may borrow what it captures, so the values it reads must outlive it (rule 4).
4. Work you start ends before the values it uses. Dropping a promise cancels it.
5. Concurrent code can read shared values but never change them. To change shared state, give it one owner and send it values over a `pipe`.
6. Errors and faults inside a promise come back from `wait` as errors. A fault outside any promise ends the program.

## HTTP server

```manuscript
export fn serve(
    address: String,
    handler: fn(HttpExchange) Unit!,   // built once, read by every thread
    options: HttpServerOptions = HttpServerOptions()   // adds cores: Int?, where none means every core
) HttpServer!

impl HttpServer:
    fn address() String
    fn wait(timeout: Duration? = none) Unit!   // until the server has stopped
    var fn close() Unit                        // stop accepting; drain within `grace`, then cancel (close itself never waits)

let router = build_router(config)
var server = try serve(":8080", router.handler())
try server.wait()
```

How it runs (in `net.ms`, apart from the native protocol code):

1. `serve` binds a plain TCP listener and runs an accept loop as a promise. Each accepted connection becomes `promise(fn: serve_connection(conn, handler, options))`, which the runtime places on the least busy thread, where it stays. The existing Rust connection code runs HTTP/1.1, HTTP/2 and the TLS handshake with `options.tls`, as `adopt` does today (`server.rs:725`).
2. The handler, router and everything they capture are built once and only read by every thread (rule 5). Logger files and HTTP clients are runtime handles, safe to use from any thread.
3. Each request runs the handler as a promise owned by its connection, placed on the connection's thread unless that thread is busy. A client disconnect or the request timeout drops that promise, which cancels the handler at its next wait.
4. `cores: 1` limits the runtime to one thread; the code is the same.
5. On `close`, SIGINT or SIGTERM, the accept loop's `wait_first` over accept and the signal stream returns. Connections drain within `grace`, then are cancelled, and `wait` returns.
6. A handler fault ends only that request's promise. The handler could not write shared state, so nothing is half-written. The connection code answers 500, as today.
7. State that changes across requests lives in an owner promise that handlers write to through a pipe.

Platforms: an accepted socket is never registered with the accepting thread's poller before handoff. On Windows, mio's AFD polling can therefore register it on the core. `serve-cores.ms` already verifies the handoff in the full matrix for plain HTTP; the PR adds a fixture that runs TLS over several cores.

Tests in one process: `serve(":0", ...)` followed by `fetch(server.address()).wait()`. `Router.call` runs a handler directly.

## Internal model (what makes it sound)

1. **One heap for the process, one scheduler per thread.** All threads allocate from one reserved region with thread-local pages, so the common path takes no lock; a block freed on another thread returns to its page's owner through the remote-free path (`alloc.rs:384`), and pages still holding live blocks when a thread goes idle are adopted by the next one (the mimalloc design).
   - One persistent thread per core (or `cores`), each with its own scheduler and poller. Load is one atomic counter per thread (promises ready plus the one running), in a flat array indexed by thread with one cache line each; nothing else is tracked. A new promise compares the current thread's count, not counting the caller itself, with the next thread's in round robin order and goes to the lower one, ties staying local. A thread starts the first time a promise is placed on it, so a program that never overlaps work runs on one thread. An idle thread takes promises that have not started yet from busy ones. A started promise never moves, so stacks and poller registrations stay on one thread. There is no core argument and no separate worker API.
   - Calls the kernel cannot wait on (file system, `getaddrinfo`, extern declarations marked blocking) run on the existing blocking pool (`glue/pool.rs`, `MS_POOL_THREADS`, default 4, DNS capped at half), and the calling promise waits on its slot. There is no second mechanism for blocking calls. Total threads are at most cores plus the pool; on Windows one poll helper thread per scheduler thread is added (`ms-std-net/src/sys/windows.rs:151`).
   - Module state is immutable after initialization, so it needs no per-thread copy.
   - Every value is freed by its owner's drop, so cancel and fault unwinding must drop stack-held values.
2. **A promise owns what it captures, or only reads what outlives it. It never writes outside state.**
   - `promise` declares in its stdlib signatures that the returned promise borrows its entry's captures (a declared attribute, not a Rust name list like `walk.rs:1157-1175`). A list of such promises (`urls.map(fn u: fetch(u))`) borrows the same roots.
   - I/O operations copy their small arguments (paths, URLs, headers), so their promises borrow nothing.
3. **Crossing threads.** Values move by pointer and borrowed captures are read in place; nothing is copied or encoded. JSON is used only where memory is not shared: processes, files and sockets.
   - This is sound because one owner means a moved value has no other reference, and rule 2 means a read borrow has no writer.
   - It requires that no value carries a shared count: runtime objects lose their refcount (below). With that, promises need no `Data` or `Send`-like bound.
   - An OS handle registered with one thread's poller is re-registered by the receiving thread on first use (today's `adopt`, made general).
4. **Dropping a promise cancels it and joins it.** At the end of a scope, promises drop before the locals they read.
5. **Cancellation happens only at waits.** A cancelled read takes no value.
6. **A fault ends its promise.** This is sound by rule 2.
   - A fault in runtime code ends the program.
7. **Only three runtime objects are touched from two threads at once, and each synchronizes internally:** a promise's result slot (written by the thread running it, read by the waiter), a pipe's queue (writers and its reader), and the process-wide stdio buffers behind `stdout()`/`stderr()`. User code cannot do this: `write` is a `var fn`, so two promises cannot share one stream; each takes its own writer.

## Deleted

`TaskGroup`, `Task`, `TaskChannel`, `WorkerGroup`, `worker_channel`, `ProcessGroup` with the `ms-std-process` fork IPC (4k lines), `Channel`, `Transport`, `channel_reader`, `channel_writer`, `Shared`, `share`, `lock`, `SharedGuard`, `Once`, per-task timeouts, `contain_faults`, `serve_cores`, `serve_core`, `serve_connections`, and in flow.ms `Cache`, `SingleFlight` and `Debounce`. By grep, `ProcessGroup`, `contain_faults`, `Once` and those three flow.ms types are unused outside their own code and fixtures.

## Migration

| Today | Becomes |
| --- | --- |
| `TaskGroup` + `spawn` + `results()` | `wait_all(xs.map(fn x: promise(fn: f(x))))` |
| `spawn(entry, timeout: d)`, `contain_faults` | `promise(fn: f()).wait(timeout: d)`; faults come back as `Failed` |
| `WorkerGroup` + `worker_channel` | `promise(fn: ...)`, plus a `pipe[T]` for a long-lived one |
| `Channel`, `channel_reader`/`writer` | `pipe[T]`; `json_reader`/`json_writer` over byte streams |
| blocking `read(path)`, `fetch`, `sleep`, stream `read` | `.wait()` on the returned promise (codemod); stream `write` call sites are unchanged |
| `for x in stream` | `for x in stream.wait()` (codemod) |
| `ReadStream`, `read(max_bytes)`, `write(String)` | `ReadStream[Bytes]`, `read_chunk`, `write_text` (codemod, about 70 files) |
| `serve` + `serve_cores` + `serve_core` + `serve_connections` | one `serve` |
| `map_concurrent` over a `Shared` cursor | `limit` promises over stripes, merged by index |
| `log.ms` `Shared` transports | each logger holds its own OS handle; rotation checks size with `fstat` |
| `router.ms` `Shared` test state | `HttpExchange` writes become `var fn` |

## Implementation (one PR)

- **Runtime (rework of internals built for the earlier concurrency):**
  - one process-wide heap with thread-local pages, replacing per-isolate arenas and their 256-slot cap (`alloc.rs:25-27,227`); `realloc` and `free` handle every block the same way (fixes the review's foreign-block findings, `alloc.rs:651,722-790`);
  - runtime objects without a refcount (`obj.rs:26` `retain`/`release`): one owner each; natives borrow instead of keeping second references (`ObjShare`/`Handed`, `ffi/native.rs:540-560`; audit their users first); function values and closures owned and moved, `.clone()` the only copy (`cabi.rs:535`);
  - remove the per-isolate string scalar-count cache (`string.rs:233-262`), keyed by address and so stale across threads, and against the no-caches rule;
  - one persistent thread per core with its own scheduler and poller; least-loaded placement and taking unstarted promises; marked blocking externs routed to the existing blocking pool;
  - internal synchronization for promise result slots, pipe queues and stdio buffers;
  - general poller adoption of handles received from another thread;
  - I/O promises as entries in a per-isolate array of `{state, token, result}` indexed by generation, no task or stack: try the system call at once, register with the poller only when it would block. Only `promise(fn)` needs a task (a task stack slot is 256 MiB of address space, `task.rs:46-60`);
  - `Pipe[T]` on the cross-thread wake path; fix the dropped remote post (`task.rs:1520`);
  - cancel-on-drop, and drop stack-held values on cancel and fault;
  - delete the old machinery: channel groups and leases (`channel.rs`), the worker JSON transport, `Shared` glue, process-group IPC.
- **Checker:**
  - rule 2, including promises as borrows;
  - the declared lending of `promise` captures;
  - an unused-promise warning;
  - `ReadStream` is not iterable, with a message pointing to `.wait()`.
- **Stdlib:** `promise.ms`, generic `io.ms`, `serve` in `net.ms`, plus `log.ms`, `router.ms` and `flow.ms`. Delete everything listed above, along with its checker and lowering glue.
- **Codemods:** the three rows marked codemod above.
- **Docs:** the concurrency guides, `references.md:10,62`, and `ms guide`.
- **Checks:**
  - `make verify-full`, `make leak-check`, the full Linux/macOS/Windows matrix, and `conc_bench`;
  - `bench/perf/web` against its latest dated result, on one core and on all cores;
  - a parallel sort of 10M `Int` against one core;
  - a 1 MB value moved to a promise on another thread against today's JSON transfer;
  - a CPU-heavy promise next to I/O promises, to size the starvation case;
  - allocation-heavy single-thread benches (`bench/perf` programs) within 5% of the latest baseline after the heap and refcount rework;
  - `read(...).wait()` against today's `read`.
- Closes #1422.

## Decisions (Chinmay, 2026-11-02)

1. `ProcessGroup` is deleted; `promise` covers parallel work and `exec` covers separate stdio.
2. `HttpExchange.send`, `send_headers`, `read` and `close` become `var fn`.
3. `serve` defaults to every core.
4. Stream implementations written in Manuscript are out of scope; they are redesigned next.
5. Promises borrow their captures; I/O operations copy small arguments.
6. Stream writes follow Node: `write` puts the value in the stream's buffer and returns at once, so it is not a promise and the 743 `let _written = stdout().write(...)` sites stay as they are. Backpressure is explicit: `flush()` returns a promise that waits for the buffer to drain, and `buffered()` reports how much is pending. Buffers left at exit are drained by the runtime before the process ends (unlike Node, where pending pipe writes can be lost). Every other dropped promise is cancelled.
7. `wait(timeout:)` on a CPU-bound promise takes effect at its next wait; documented, no back-edge polling.
8. One heap for the whole process; values move between threads by pointer, never copied.
9. Runtime objects lose their refcount; closures are owned. Internals built for the earlier concurrency are reworked in this PR.
10. Size: the 1,270 `stdout().write(` sites no longer change; the remaining call sites (reads, `sleep`, `fetch`, stream loops) are re-counted at the start of implementation. The codemod edits the syntax tree, Markdown fences included. One PR, ordered as reviewable commits: heap and refcount rework with tests; promise runtime and checker rules; generic `io.ms`; mechanical codemod commits; multi-thread placement and `pipe`; `serve`; deletions; docs.
11. One `promise` for all work; the runtime picks the thread (replaces `worker` and the fresh isolate per worker). A started promise never migrates; migration is added only if measurements show starvation.

