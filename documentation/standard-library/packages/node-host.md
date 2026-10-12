+++
title = "Filesystem, OS, process, paths, and timers"
weight = 62
+++

# Filesystem, OS, process, paths, and timers

[Coverage](coverage.md) · [Common contracts](contracts.md) · [Conformance](conformance.md)

These capabilities cover the native application tasks in Node.js 24's `fs/promises`, `os`, `path`, `process`, and `timers` packages. They use Manuscript names, explicit capabilities, owned results, optional read budgets, and lexical cleanup. Filesystem, path, process, system, and timer errors use their package-specific `Error` implementations; a common `Result[T, Error]` boundary accepts them directly and supports `try`. They are not drop-in JavaScript APIs. The tables below distinguish functional equivalents, native OS limitations, and facilities specific to Node's VM and event loop. The baseline is Node.js 24.19.0: 181 module exports and returned-resource methods, including `timers/promises`. An `adapted` mapping supplies the native operation through Manuscript's bounds, types, authority, or execution lifetimes; `runtime_specific` records Node facilities outside that execution model. The checked inventory in `pkg/compiler/testdata/node-host-coverage.json` records every public export in the baseline; it does not claim that recording an API establishes identical behavior.

## Files and directories

Import `filesystem()` from `@std/fs.ms` for path operations. Acquire handles inside `with`. This fragment belongs in a function returning `Result[Unit, FileSystemError]`:

```manuscript
with file = try filesystem().open(path: path, flags: "r+", mode: 384):
    let written = try file.write_at(offset: 0, data: "HELLO".to_bytes())
    let bytes = try file.read_at(offset: 0, max_bytes: 5)
    let synced = try file.sync()
```

These calls run in the native CLI conformance fixture `tests/e2e/testdata/projects/library/main.ms`. `384` is decimal for Unix permission bits `0600`. Opening accepts `r`, `r+`, `w`, `wx`, `w+`, `wx+`, `a`, `ax`, `a+`, and `ax+`. `x` makes creation exclusive. Permission arguments accept `0..4095` (`07777`), including setuid, setgid, and sticky bits where the native OS supports them. `open_flags` accepts numeric native flags from `fs.constants()`; these numbers are host-specific. Paths use the native filesystem dialect, reject NUL, and use host OS permissions. Relative paths on CLI roots use the live working directory; embedded capabilities constructed with a directory retain that base. Imports confer no filesystem authority.

| Node.js facility | Manuscript operation |
| --- | --- |
| `access` | `FileSystem.access`; access-mode constants from `fs.constants()` |
| `appendFile`, `writeFile`, `readFile` | `append_file`, `write_file`, bounded `read_file`; strict codecs are separate |
| `chmod`, `lchmod`, `chown`, `lchown` | `chmod`, `chmod_link`, `chown(follow_links: ...)` |
| `copyFile`, `cp` | `copy_file`, `copy_tree`, and bounded `copy` with `CopyOptions` and an optional filter |
| `mkdir`, `mkdtemp`, `mkdtempDisposable` | `create_directory`, `temporary_directory`, scoped `temporary` |
| `open`, `opendir`, `readdir` | `open`/`open_flags`, `open_directory`, bounded sorted `list` |
| `stat`, `lstat`, `statfs` | `stat(follow_links: ...)`, `stat_filesystem` |
| `link`, `symlink`, `readlink`, `realpath` | `hard_link`, `create_link`, `read_link`, `canonicalize` |
| `rename`, `rm`, `rmdir`, `unlink` | `rename`, `remove(recursive: ...)` |
| `truncate`, `utimes`, `lutimes` | `truncate`, `set_times(follow_links: ...)` |
| `glob` | `glob`, or typed `glob_entries` with `GlobOptions` and an optional exclusion callback |
| `watch` | Native `watch_native`, or polling `watch`; both are scoped and cancellable |
| `constants` | `fs.constants()` exposes native access, mode, open, and copy flags |

`FileHandle` supports sequential `read`/`write`, positional `read_at`/`write_at`, bounded `read_file`, `write_file`, `append_file`, `read_vectors`/`write_vectors`, `read_lines`, `seek`, `stat`, `truncate`, `chmod`, `chown`, `set_times`, `sync`, `data_sync`, and idempotent `close`. A chunk read returns up to 64 KiB; sequential EOF is `none`, positional EOF is empty `Bytes`. `read_vectors` accepts each size up to 64 KiB and a combined size up to 16 MiB. Vector offset `-1` uses the current position. Seek origins are `0` (start), `1` (current), and `2` (end). `read_file`, `write_file`, and `read_lines` start at the current position. Line reads validate UTF-8, remove line terminators, and enforce both byte and line limits.

`reader()` and `writer()` adapt the same handle to the existing stream contracts, translating `FileSystemError` into `IoError`. Closing an adapter closes the handle and every alias. `flush` synchronizes the file; this is stronger than flushing a userspace buffer. Operations serialize shared file positions. Close prevents new calls, interrupts pollable I/O, and joins admitted calls. Parent cancellation unwinds; it is not EOF. Acquisition releases a resource when cancellation wins before delivery. Regular-file OS calls can delay cancellation until they return.

Directory cursors expose their native `path()` and return one `DirectoryEntry` or `none` and require close. Temporary resources recursively remove their directory at scope exit. `FileInfo.mode` contains POSIX type and permission bits; `permissions` contains only permission/special bits. The record supplies size, modified/accessed/changed times, optional `created` birth time, block size/allocation, device/inode/link count, owner IDs, and regular/symlink/directory/FIFO/socket/device classifications. `exact` contains arbitrary-precision numeric metadata and nanosecond timestamps. Native fields absent on a host are zero; unavailable birth time is `none`. Accessed/changed times fall back to modified time when unavailable, including the current Windows adapter.

`copy` accepts `CopyOptions`: recursive traversal, replacement, error-on-existing, dereferencing, timestamp preservation, verbatim symlinks, clone policy (`none`, `try`, or `force`), and shared entry/byte budgets. An optional filter runs sequentially for each source/destination pair and can prune directories. Without dereferencing, links are copied as links; relative targets are resolved against the source unless verbatim copying is requested. Dereferencing detects ancestor cycles. Copy rejects copying a tree into itself and traversing a destination symlink as a directory. Existing directories merge; collisions skip, fail, or replace according to the options. Native cloning uses Linux reflinks or macOS clonefile; `try` falls back to byte copying and `force` reports an OS error when unavailable. Windows has no clone adapter. The root and descendants share `max_entries`; all copied data shares `max_bytes`. Copying and writing can leave a partial prefix after an error.

`watch_native` retains OS events while the caller is busy. It bounds directory watches with `max_entries` and buffered events with `max_events`; overflow policy `error` returns `LimitExceeded`, while `ignore` drops excess events. Recursive watches admit newly created directories and do not follow directory symlinks. Events use `rename` for creation/removal/rename and `change` for writes/metadata changes. OS backends can coalesce events, report a containing directory, or overflow; event names and granularity are platform-dependent. Close stops the backend and joins its worker and admitted waiter. Cancellation during acquisition releases the backend.

Polling `watch` compares bounded snapshots after each requested interval. They report sorted `FileEvent` records with `rename` for appearance/disappearance and `change` for changed metadata. A vanished root reports disappearance. Recursive watches do not follow symlinks. Polling can coalesce or miss transient changes between snapshots; this is not a native OS event stream. Close and parent cancellation interrupt a waiting `next` without leaving a worker running.

## Paths

Import pure path functions from `@std/path.ms`, or use `posix()`/`win32()` for a dialect independent of the host. No path operation reads cwd or touches files.

| Node.js facility | Manuscript operation |
| --- | --- |
| `basename(path, suffix)` | `basename`, `basename_without` |
| `dirname`, `extname`, `normalize`, `isAbsolute`, `join` | `dirname`, `extension`, `normalize`, `is_absolute`, `join` |
| `parse`, `format` | `parse`, `format`, `PathParts` |
| `resolve`, `relative` | `resolve(base: absolute_path, parts: ...)`, `relative` with absolute inputs |
| `sep`, `delimiter`, `posix`, `win32` | `separator()`, `delimiter()`, `posix()`, `win32()` |
| `toNamespacedPath` | `to_namespaced_path` for absolute Windows drive/UNC paths; relative paths pass through |
| `matchesGlob` | `matches_glob` |

Windows parsing preserves the spelling of separators. Normalization emits backslashes. UNC and drive roots remain distinct; relative comparisons are case-insensitive for Windows. Drive-relative components use an earlier explicit absolute base on the chosen drive; an unknown drive base returns `InvalidInput`, since resolving it would require ambient per-drive cwd. Later absolute components supersede earlier paths. Relative identical paths produce an empty string. `PathParts.directory` and `base` take precedence over `root`, `name`, and `extension` when formatting.

Globs support segment wildcards, character classes, `**`, brace alternatives, numeric brace ranges, and `@`, `+`, `?`, `*`, `!` extended groups. Hidden segments require an explicit leading dot. Patterns are limited to 4096 bytes; numeric ranges have at most 1025 entries and endpoints within `-100000..100000`. Use `/` between filesystem glob segments on every host. Brace alternatives can cross directory separators; alphabetic and padded numeric ranges are supported. Basic filesystem `glob` returns sorted relative paths without following directory symlinks; its `max_entries` bounds matched output. `glob_entries` accepts multiple patterns, pattern/callback exclusions that prune traversal, optional link following with cycle prevention, and separate visited-entry/result limits. Results are sorted, deduplicated `PathEntry` records. Absolute and parent-relative patterns can visit outside the supplied base, within the authority granted by the filesystem capability.

## OS and current process

Import `system()` from `@std/system.ms` for OS queries, and `control()` and `commands()` from `@std/process.ms`. `system()` supplies OS queries. `control()` supplies current-process authority; `commands()` continues to run bounded, joined child commands. CLI `arguments()` and `environment()` retain startup snapshots; request a fresh environment through the control capability after mutation.

| Node.js facility | Manuscript operation |
| --- | --- |
| `os.arch`, `platform`, `availableParallelism` | `System.info`, `System.metrics.available_parallelism` |
| `type`, `endianness`, `EOL`, `devNull` | Pure `os_type()`, `endianness()`, `end_of_line()`, `dev_null()` |
| `homedir`, `tmpdir`, `hostname`, `userInfo` | `home_directory`, `temporary_directory`, `hostname`, `user_info` |
| `cpus`, `freemem`, `totalmem`, `uptime`, `loadavg` | `cpus`, `metrics` |
| `networkInterfaces` | `network_interfaces`, one record per address |
| `release`, `version`, `machine` | `os_release`, `os_version`, `machine` |
| `getPriority`, `setPriority`, `constants` | `get_priority`, `set_priority`, `system.constants()` |
| `process.pid`, `ppid`, `argv`, `argv0`, `execPath`, `platform`, `arch`, identity getters | `ProcessControl.info`, `arguments()` |
| `env`, `loadEnvFile` | `environment`, `set_environment`, bounded `load_environment` |
| `cwd`, `chdir` | `working_directory`, `change_directory` |
| `memoryUsage`, `cpuUsage`, `resourceUsage`, `uptime`, `hrtime` | `memory_usage`, `cpu_usage`, `resource_usage`, `uptime`, `monotonic_time` (nanoseconds), or host monotonic `Clock` |
| `getgroups`, identity setters, `setgroups`, `umask` | `groups`, `set_identity`, `set_groups`, `initialize_groups`, `umask` |
| `execve`, `title`, `constrainedMemory`, `availableMemory` | `replace`, `title`/`set_title`, `constrained_memory`, `available_memory` |
| `kill` | `send_signal` and scoped `watch_signals` with native signal numbers |
| `stdin`, `stdout`, `stderr`, `openStdin` | Explicit process stream fields |
| `exit`, `exitCode` | Return an exit code from `main`, after scoped cleanup and joins |

Architecture names follow Go (`amd64`, `arm64`), rather than Node (`x64`, `arm64`). `memory_usage` describes the Go heap; it is not a V8 heap report. `metrics.available_parallelism` queries native usable processors, including Linux affinity and Windows processor groups. CPU accounting is in microseconds for processes and milliseconds for CPU records. The environment loader accepts an optional `export` prefix, quotes including multiline values, and comments outside quotes. It validates all entries before writing; existing variables win. Changing cwd/environment/identity/umask is process-wide authority and affects subsequent host operations. `umask` returns the previous mask; permission and priority changes can fail under OS policy.

CPU, memory, uptime, OS release/version, and resident-process memory use native Linux, macOS, and Windows queries through pinned, vendored adapters. Windows load averages are three zeros. User shell comes from native macOS user records or local Linux passwd entries; it is empty on Windows or when no local Linux shell is available. Linux and macOS implement filesystem statistics, process CPU/resource accounting, priorities, identities, groups, umask, and descriptor timestamp updates. Linux no-follow chmod is unsupported, as in Node; macOS supports no-follow chmod and timestamps. Windows implements filesystem statistics, descriptor timestamps, process CPU/resource usage, console titles, and native priority-class mapping. Windows identity/group/umask changes, exec replacement, and no-follow metadata updates return `Unsupported`. Windows permission bits express its native read/write policy rather than POSIX ownership. `system.constants()` flattens native signal, errno, dlopen, and priority names; Linux catalogs are compared against Node in tests. Constants are host-specific; only supported native values are exported on other hosts.

`watch_signals` returns a scoped `SignalStream` with a bounded delivery buffer. OS/Go signal delivery can coalesce or drop repeated signals; SIGKILL and SIGSTOP cannot be observed. The CLI still treats SIGINT/SIGTERM as cancellation, and an observer does not override joined shutdown. Unix `send_signal` accepts signed PIDs for process groups and signal zero for existence checks. Windows supports existence checks and forced termination for its INT/KILL/TERM mapping; other signals return `Unsupported`.

Node-only process facilities (VM configuration/version information, JavaScript module loading, V8 reports/profiling hooks, source maps, promise rejection/exception hooks, JavaScript finalization, IPC integration, EventEmitter events, and ref/unref of an event loop) have no direct equivalent. `nextTick` scheduling is replaced by explicit ordinary calls, `yield_now`, joined tasks, or `Scheduler`. Immediate abort and VM-thread CPU accounting remain outside Manuscript execution lifetimes. Process titles use Linux kernel names (at most 15 UTF-8 bytes), macOS program names, or Windows console titles. They do not rewrite argv. Linux constrained-memory queries inspect the current cgroup v1/v2 memory controller; zero means no known limit. Available memory is the lesser of host available memory and the remaining known cgroup budget. On other hosts, constrained memory is zero (unknown), and available memory uses the native host query. `initialize_groups` resolves a user's supplementary groups and applies them under native privilege checks. Unix `replace` supplies an explicit argv and environment and replaces the executable; success never returns and bypasses scoped cleanup, just as native exec does. Use ordinary `Commands.run` when the caller must retain its execution lifetime. The inventory records these differences explicitly.

## Timers and scheduling

Use [Scheduler](../tasks/scheduler.md) from `@std/tasks.ms` for concurrent immediate, delayed, and repeating work. Sequential delays use `sleep` from `@std/time.ms`. All scheduled work uses operation IDs, cancellation, status, failure reporting, and the scheduler's joined lifetime.

| Node.js operation | Manuscript operation |
| --- | --- |
| `setTimeout` | `scheduler.after(duration: ..., operation: ...)` |
| `setInterval` | `scheduler.every(interval: ..., operation: ...)` |
| `setImmediate` | `scheduler.after` with zero delay |
| Clear/disposal | `scheduler.cancel(id)`; scheduler close joins work |
| Timeout `refresh` | `scheduler.restart(id)` returns a fresh operation ID |
| Promise timeout/interval | Ordinary sleep or a sequential sleep loop |
| Promise scheduler wait/yield | `sleep` and `yield_now` |

Repeating callbacks never overlap, and the next delay begins after completion. This preserves bounded callback backlog rather than Node event-loop tick timing. Scheduling has no JS event-loop phase ordering or ref/unref lifetime. The offline Node host inventory (`pkg/compiler/testdata/node-host-coverage.json`) and native CLI fixtures track these adaptations.
