+++
title = "Commands and processes"
weight = 12
+++

# Commands and processes

API reference: [process](reference/process.md) and [io](reference/io.md).

Use stream helpers for bounded reads and copies, and Commands for buffered or long-lived subprocess execution. The caller supplies the streams or command service. Helpers do not acquire authority or close the streams for you.

## Running commands

The bounded subprocess facility is exported by `@std/process.ms`. Import `commands() -> Commands` from `@std/process.ms` to obtain the host command service:

`Commands.run` and `CommandOutput` are declared in the [`@std/process.ms` reference](reference/process.md).

Omit `input` for empty standard input; `commands().run(program: "tool", arguments: [])` evaluates fresh empty bytes on each call. Supplied bytes are passed unchanged. The same default works through a stored method or a source implementation of `Commands`.

`CommandError` has `InvalidInput`, `Unavailable`, `Timeout`, `OutputLimit`, and `Failed(message: String)`. Empty/NUL program names, NUL arguments, negative bounds, and negative timeout return InvalidInput. The total stdout plus stderr bound is nonnegative. Nonzero ordinary exit is an `ok` output with that code. Timeout or output overflow stops and joins the process before returning its error; caller cancellation unwinds after joining. POSIX process groups include descendants in termination.

On platforms without process-group support the wrapper controls the direct process, with bounded pipe completion; descendant supervision needs a platform host contract. [Managed subprocesses](#managed-subprocesses) cover interactive streams; [network sockets](network.md), [streaming HTTP](http.md) and [WebSockets](websocket.md) are implemented.

## Stream helpers

These helpers use shared stream views without closing them. Keep the streams' own cleanup scopes open for the whole call. All helpers cooperate with cancellation and enforce cumulative byte limits.

| Helper | Behavior |
| --- | --- |
| `copy` | Returns the number of bytes copied. An error may occur after a prefix was written; there is no rollback. |
| `read_all` | Returns all bytes only on success. |
| `read_line` | Reads through LF, strips it and a preceding CR, and accepts a final line without a terminator. Native streams buffer read-ahead and retain the remainder for subsequent line or chunk reads after a successful line; source-defined streams read one byte at a time. |

`read_line` returns `none` only if EOF occurs before any data. Its positive `max_bytes` includes terminator bytes. Invalid UTF-8 returns `InvalidData`; overflow returns `LimitExceeded` and may consume data already fetched, including a native read-ahead chunk. A line budget does not reduce the native chunk size or guarantee that overflow preserves the next line. Copy and read_all allow a zero limit for an empty source.

Source streams must return nonempty chunks within the requested size. A malformed stream implementation causes `Failed`.

Expected stream failures preserve their original `IoError` case and payload. Invalid UTF-8 returns `IoError.InvalidData`; an exceeded byte bound returns `IoError.LimitExceeded`. Helpers do not flatten Result or catch cancellation and faults. Convert a File view explicitly to ReadStream when required by the contract-view rules.

## Managed subprocesses

`commands().spawn(program, arguments)` starts a long-lived child and returns `Result[Subprocess, CommandError]`. Acquire it with `with` so scope exit, return, error, and cancellation close it:

```manuscript
import {commands} from "@std/process.ms"
import {read_line} from "@std/io.ms"
import panic from "@std/faults.ms"

fn echo_once() -> Unit:
    match commands().spawn(program: "cat", arguments: []):
        error(cause): return panic(message: "spawn failed")
        ok(child):
            with running = child:
                running.stdin().write("ping\n".to_bytes())
                running.stdin().close()
                read_line(input: running.stdout())
```

`Subprocess` exposes `stdin()`, `stdout()`, `stderr()` (shared `WriteStream`/`ReadStream` views of OS pipes), `wait(timeout)`, `terminate()`, `kill()`, and `close()`. Pipes give natural backpressure: a full pipe blocks the writer, and unread output blocks the child, so nothing is buffered without bound. Closing `stdin()` delivers EOF to the child.

- `wait` returns the exit code (`-1` if a signal ended the child). `timeout` expires with `TimedOut` and leaves the child running; caller cancellation unwinds without killing it, because scope exit does that. After exit, `wait` keeps returning the recorded status, including after `close`.
- `terminate` sends SIGTERM to the process group and `kill` sends SIGKILL; neither waits. Windows has no SIGTERM, so `terminate` kills the direct process.
- `close` is idempotent. It kills the process group, joins the child, kills any descendants still in the group, and closes all three streams. Unread output is discarded and later stream operations return `Closed`. Cancelling the acquiring execution also kills the group. Aliases to the streams or `Subprocess` do not extend the lifetime.
- Races: stream EOF can arrive before or after exit (descendants may keep a pipe open), so `wait` is the authority on exit. Output written before exit stays readable until `close`. A read or write blocked when `close` runs returns `Closed`.
- Readiness is observed by reading `stdout()` or `stderr()` (for example `read_line` until a ready line); no sleep polling is needed.

POSIX hosts place the child in its own process group, so descendants are cleaned up. Other platforms supervise only the direct process. Environment, working-directory, and pseudo-terminal controls are not part of this contract.

## Current process control

Import `control()` from `@std/process.ms` to query or change the current process. Its [reference](reference/process.md) lists directory, environment, identity, resource, and signal operations. Directory and environment changes affect subsequent host calls.

| View | Contract |
| --- | --- |
| `cli.arguments()` | Host-supplied startup tail, excluding the executable; test roots supply an empty list. |
| `ProcessInfo.arguments` | Native `os.Args` read by `info()`, including `argv[0]`; it is not the CLI accessor's supplied tail. |
| `cli.environment()` | Startup map retained by the execution's host roots. Repeated calls return the same mutable map. |
| `System.environment(name)` | Live OS lookup; absent or non-UTF-8 values return `none`. |
| `ProcessControl.environment()` | Fresh live OS map; non-UTF-8 entries return `ProcessError.Unsupported`. |
| `set_environment` / `load_environment` | Mutate the live process environment. They do not refresh the CLI map. |
| `System.working_directory()` | Live cwd on CLI roots, fixed base on a host constructed with a directory; an OS failure faults. |
| `ProcessControl.working_directory()` | Live cwd query whose failures are `ProcessError` values. |

The CLI list/map can be changed through ordinary collection mutation; that changes the retained view, not native argv or environment. Clone them when a separate snapshot is required. Directory/environment mutation is process-wide, so concurrent operations can observe changes.

`memory_usage` reports the runtime heap and resident-process memory. `load_environment` accepts an optional `export` prefix, quoted multiline values, and comments outside quotes. It validates every entry before writing; existing variables win. `umask` accepts `0..511` (`0777`) and returns the previous mask. `set_identity` accepts exactly the case-sensitive strings `uid`, `gid`, `euid`, and `egid`, with IDs in `0..2147483647`; other input returns `InvalidInput`. Identity, permission, and priority changes are subject to OS policy.

Linux and macOS support process resource accounting, identities, groups, and umask. Windows supports resource accounting, console titles, and native priority classes; identity/group/umask changes and executable replacement return `Unsupported`.

## Process time and accounting

`uptime()` is a Duration measured since native runtime initialization. `monotonic_time()` is the same elapsed span as an Int in **nanoseconds**, with the same runtime-initialization origin. It is not a Unix timestamp, CPU time, or an Instant from a Clock. `SystemMetrics.uptime` instead measures host boot uptime, at whole-second native resolution. Prefer `clock().now()` and `Instant.difference` for elapsed measurements; see [time values](system.md#time-value-methods).

`CpuUsage.user_microseconds`/`system_microseconds` and the corresponding ResourceUsage fields are cumulative process CPU microseconds. `max_resident_bytes` is peak resident memory in bytes. Fault, filesystem-I/O and context-switch fields are counts: Unix filesystem counters count block I/O, while Windows counters count I/O operations and unavailable fault/context-switch fields are zero. MemoryUsage fields and constrained/available memory are bytes. Host CpuInfo counters use milliseconds, and speed_mhz is integer MHz.

## Signals

`watch_signals` returns a scoped `SignalStream` with a bounded delivery buffer. The signal list must be nonempty; numbers must be `1..64`, excluding SIGKILL and SIGSTOP. A supplied capacity must be `1..1048576` (omission/`none` uses 128). Range validation does not guarantee that every number denotes a supported signal on every OS. Use `system.constants()` and handle absent names. OS signal delivery can coalesce or drop repeated signals; SIGKILL and SIGSTOP cannot be observed. The native host still treats SIGINT/SIGTERM as cancellation. A watcher only observes; it cannot claim a signal or protect code after `next()`. Use registered `with`/`Closeable` cleanup for shutdown, and finish required writes directly in the shielded close call after joining cancelled workers. See the [shutdown cookbook](../concurrency/shutdown.md) for runnable examples and limitations. `send_signal` validates a signed 32-bit PID and signal `0..64`; the native OS decides whether the selected number/target is supported. Unix `send_signal` accepts signed PIDs for process groups and signal zero for existence checks. Windows supports existence checks and forced termination for its INT/KILL/TERM mapping; other signals return `Unsupported`.

## Titles, memory, and replacement

Process titles use Linux kernel names (at most 15 UTF-8 bytes), macOS program names, or Windows console titles. They do not rewrite argv. Linux constrained-memory queries inspect the current cgroup v1/v2 memory controller; zero means no known limit. Available memory is the lesser of host available memory and the remaining known cgroup budget. On other hosts, constrained memory is zero (unknown), and available memory uses the native host query. `initialize_groups` resolves a user's supplementary groups and applies them under native privilege checks. Unix `replace` supplies an explicit argv and environment and replaces the executable; success never returns and bypasses scoped cleanup, just as native exec does. Use ordinary `Commands.run` when the caller must retain its execution lifetime.
