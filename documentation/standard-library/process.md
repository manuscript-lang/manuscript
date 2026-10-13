+++
title = "Commands and processes"
weight = 12
+++

# Commands and processes

API reference: [process](reference/process.md) and [io](reference/io.md).

Use stream helpers for bounded reads and copies, and Commands for buffered subprocess execution. The caller supplies the streams or command service. Helpers do not acquire authority or close the streams for you.

## Running commands

The bounded subprocess facility is exported by `@std/process.ms`. Import `commands() -> Commands` from `@std/process.ms` to obtain the host command service:

```manuscript
# Commands
fn run(program: String, arguments: List[String], input: Bytes,
       max_output_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[CommandOutput, CommandError]

type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes
```

`CommandError` has `InvalidInput`, `Unavailable`, `TimedOut`, `OutputLimit`, and `Failed(message: String)`. Empty/NUL program names, NUL arguments, negative bounds, and negative timeout return InvalidInput. The total stdout plus stderr bound is nonnegative. Nonzero ordinary exit is an `ok` output with that code. Timeout or output overflow stops and joins the process before returning its error; caller cancellation unwinds after joining. POSIX process groups include descendants in termination.

On platforms without process-group support the wrapper controls the direct process, with bounded pipe completion; descendant supervision needs a platform host contract. Interactive subprocess streams remain separate future contracts; [network sockets](network.md), [streaming HTTP](http.md) and [WebSockets](websocket.md) are implemented.

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

Commands return buffered output. Interactive child-process streams are not available.

## Current process control

Import `control()` from `@std/process.ms` to query or change the current process. Its [reference](reference/process.md) lists directory, environment, identity, resource, and signal operations. Directory and environment changes affect subsequent host calls; CLI argument and environment accessors retain their startup snapshots.

`memory_usage` reports the runtime heap and resident-process memory. `load_environment` accepts an optional `export` prefix, quoted multiline values, and comments outside quotes. It validates every entry before writing; existing variables win. `umask` returns the previous mask. Identity, permission, and priority changes are subject to OS policy.

Linux and macOS support process resource accounting, identities, groups, and umask. Windows supports resource accounting, console titles, and native priority classes; identity/group/umask changes and executable replacement return `Unsupported`.

## Signals

`watch_signals` returns a scoped `SignalStream` with a bounded delivery buffer. OS signal delivery can coalesce or drop repeated signals; SIGKILL and SIGSTOP cannot be observed. The CLI still treats SIGINT/SIGTERM as cancellation, and an observer does not override joined shutdown. Unix `send_signal` accepts signed PIDs for process groups and signal zero for existence checks. Windows supports existence checks and forced termination for its INT/KILL/TERM mapping; other signals return `Unsupported`.

## Titles, memory, and replacement

Process titles use Linux kernel names (at most 15 UTF-8 bytes), macOS program names, or Windows console titles. They do not rewrite argv. Linux constrained-memory queries inspect the current cgroup v1/v2 memory controller; zero means no known limit. Available memory is the lesser of host available memory and the remaining known cgroup budget. On other hosts, constrained memory is zero (unknown), and available memory uses the native host query. `initialize_groups` resolves a user's supplementary groups and applies them under native privilege checks. Unix `replace` supplies an explicit argv and environment and replaces the executable; success never returns and bypasses scoped cleanup, just as native exec does. Use ordinary `Commands.run` when the caller must retain its execution lifetime.
