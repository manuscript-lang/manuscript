# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import ReadStream from "@std/io.ms"
import WriteStream from "@std/io.ms"

# Errors returned when a process cannot start, times out, or exceeds an output bound.
export type CommandError:
    # The program name is empty, or the program, an argument, or a limit holds a NUL byte or is negative.
    case InvalidInput
    # The program could not be found or executed, such as a missing executable.
    case Unavailable
    # The command was still running when `timeout` elapsed, and its process group was killed.
    case Timeout
    # The combined standard output and error exceeded `max_output_bytes`, and the command was killed.
    case OutputLimit
    # The command could not be started or run for another reason reported by the host.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name paths.
        message: String
    )

# Captured exit status and standard output/error from a completed command.
export type CommandOutput:
    # The child's exit status; 0 conventionally means success. A nonzero status is still an Ok result, and a child ended by a signal reports -1 on Unix.
    exit_code: Int
    # Everything the child wrote to standard output, as raw bytes that may not be valid UTF-8.
    stdout: Bytes
    # Everything the child wrote to standard error, as raw bytes that may not be valid UTF-8.
    stderr: Bytes

# Runs child programs with empty input by default, optional output bounds and timeout.
export interface Commands:
    # Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
    # Output beyond `max_output_bytes` in total across both streams returns OutputLimit, `timeout` returns Timeout, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = "".to_bytes(),
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[CommandOutput, CommandError]
    # Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess for use with `with`. `arguments` follow the program name; stdin, stdout, and stderr are OS pipes. Returns InvalidInput, Unavailable, or Failed when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
    fn spawn(
        program: String,
        arguments: List[String]
    ) -> Result[Subprocess, CommandError]

# A long-lived child process with live stdin, stdout, and stderr pipes. Closing it
# kills the child's process group, joins it, and closes all three streams.
export interface Subprocess:
    # The child's standard input as a WriteStream; writes block when the pipe is full. Closing the stream delivers end-of-input to the child.
    fn stdin() -> WriteStream
    # The child's standard output as a ReadStream over the OS pipe; reads block until output or end-of-file, and nothing is buffered without bound.
    fn stdout() -> ReadStream
    # The child's standard error as a ReadStream over the OS pipe, with the same blocking and backpressure behavior as stdout.
    fn stderr() -> ReadStream
    # Waits for the child to exit and returns its exit status. Returns Timeout if `timeout` elapses first, leaving the child running.
    fn wait(timeout: Optional[Duration] = none) -> Result[Int, CommandError]
    # Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it kills the direct process. Does not wait.
    fn terminate() -> Unit
    # Sends SIGKILL to the child's process group. Does not wait.
    fn kill() -> Unit
    # Kills the process group, joins the child, kills leftover group members, and closes all three streams. Idempotent; `with` calls it on scope exit.
    fn close() -> Unit

# Process and operating-system controls for the current process.
# `watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
# `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup
# and finish shutdown work directly in the shielded close call after joining cancelled workers.
export interface ProcessControl:
    # Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
    # This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.
    fn monotonic_time() -> Int
    # Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
    # Capacity must be 1..1048576; omission/none uses 128 buffered signals.
    # Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
    # Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
    fn watch_signals(
        signals: List[Int],
        capacity: Optional[Int] = none
    ) -> Result[SignalStream, ProcessError]
    # Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
    fn constrained_memory() -> Result[Int, ProcessError]
    # Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
    fn available_memory() -> Result[Int, ProcessError]
    # Returns the current process title.
    # Platforms that cannot read it return Unsupported.
    fn title() -> Result[String, ProcessError]
    # Sets the process title shown by tools such as `ps`.
    # A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.
    fn set_title(title: String) -> Result[Unit, ProcessError]
    # Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
    # A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.
    fn initialize_groups(username: String, gid: Int) -> Result[Unit, ProcessError]
    # Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
    # `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.
    fn replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) -> Result[Unit, ProcessError]
    # Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
    # Text that is not valid UTF-8 returns Unsupported.
    fn info() -> Result[ProcessInfo, ProcessError]
    # Returns heap and resident memory statistics for this process, in bytes.
    fn memory_usage() -> Result[MemoryUsage, ProcessError]
    # Returns cumulative user and kernel CPU time consumed by this process in microseconds.
    # Platforms without resource accounting return Unsupported.
    fn cpu_usage() -> Result[CpuUsage, ProcessError]
    # Returns elapsed Duration since runtime initialization, rather than host boot.
    fn uptime() -> Result[Duration, ProcessError]
    # Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
    fn environment() -> Result[Map[String, String], ProcessError]
    # Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
    # An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.
    fn set_environment(
        name: String,
        value: Optional[String]
    ) -> Result[Unit, ProcessError]
    # Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
    # Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.
    fn load_environment(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, ProcessError]
    # Reads the live process directory, preserving OS failures as ProcessError.
    fn working_directory() -> Result[String, ProcessError]
    # Changes the working directory of the whole process, affecting relative paths everywhere.
    # A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.
    fn change_directory(path: String) -> Result[Unit, ProcessError]
    # Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
    # Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.
    fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
    # Returns the numeric ids of the supplementary groups of the process.
    # Windows returns Unsupported.
    fn groups() -> Result[List[Int], ProcessError]
    # Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
    # Platforms without them return Unsupported.
    fn resource_usage() -> Result[ResourceUsage, ProcessError]
    # Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
    fn umask(mask: Int) -> Result[Int, ProcessError]
    # Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
    # Identity changes require OS permission and are Unsupported on Windows.
    fn set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
    # Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
    # Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.
    fn set_groups(groups: List[Int]) -> Result[Unit, ProcessError]

# Identity and invocation details for the current process.
export type ProcessInfo:
    # Operating system id of this process.
    pid: Int
    # Operating system id of the parent process at the time of the call.
    parent_pid: Int
    # Absolute path of the running program file.
    executable: String
    # Live native argv including argv[0]; cli.arguments() is the supplied startup tail without it.
    arguments: List[String]
    # Operating system name in Go's naming, such as `linux`, `darwin`, or `windows`.
    os: String
    # Processor architecture in Go's naming, such as `amd64` or `arm64`.
    architecture: String
    # Real user id; -1 on Windows, where ids are not numeric.
    uid: Int
    # Real group id; -1 on Windows, where ids are not numeric.
    gid: Int
    # Effective user id used for permission checks; -1 on Windows.
    effective_uid: Int
    # Effective group id used for permission checks; -1 on Windows.
    effective_gid: Int

# Memory statistics for the current process; every field is bytes.
export type MemoryUsage:
    # Bytes of heap memory occupied by live objects and objects not yet collected.
    heap_used: Int
    # Bytes of heap spans currently in use, which is at least `heap_used`.
    heap_total: Int
    # Bytes of heap memory obtained from the operating system, including idle spans.
    heap_system: Int
    # Bytes the runtime obtained from the operating system outside the heap, such as stacks and internal tables.
    external: Int
    # Bytes of physical memory the operating system reports as resident for the process.
    resident: Int

# Cumulative CPU time consumed by the current process, in integer microseconds.
export type CpuUsage:
    # User CPU time in microseconds.
    user_microseconds: Int
    # Kernel CPU time in microseconds.
    system_microseconds: Int

# Kernel resource counters for the current process. CPU times are integer microseconds;
# max_resident_bytes is bytes; other fields are counts, not durations or byte totals.
# Filesystem reads/writes count native block I/O on Unix and I/O operations on Windows.
# Unavailable Windows fault/context-switch counters are zero.
export type ResourceUsage:
    # Cumulative CPU time spent running this process's own code, in microseconds.
    user_microseconds: Int
    # Cumulative CPU time the kernel spent on behalf of this process, in microseconds.
    system_microseconds: Int
    # Peak physical memory the process has held at once, in bytes.
    max_resident_bytes: Int
    # Page faults served without disk I/O, as a count.
    minor_faults: Int
    # Page faults that required disk I/O, as a count.
    major_faults: Int
    # Block input operations charged to the process, as a count.
    filesystem_reads: Int
    # Block output operations charged to the process, as a count.
    filesystem_writes: Int
    # Context switches where the process gave up the CPU, such as to wait for I/O, as a count.
    voluntary_switches: Int
    # Context switches where the scheduler preempted the process, as a count.
    involuntary_switches: Int

# A cancellable observer of operating-system signals selected by `watch_signals`.
# SIGINT/SIGTERM still cancel the native application; `close()` unregisters this observer.
# `next()` and following code have no shutdown guarantee; use registered `with`/`Closeable` cleanup.
export interface SignalStream:
    # Stops observing signals, wakes a pending `next` with Closed, and waits for it.
    # Safe to call repeatedly.
    fn close() -> Unit
    # Waits for the next observed signal and returns its number. Signals arriving while no call waits are buffered up to the stream's capacity.
    # Returns Closed after `close`. Cancelling the waiting task unwinds it.
    fn next() -> Result[Int, ProcessError]

# Errors returned by process-control operations.
export type ProcessError:
    # An argument is outside its documented range or contains NUL, such as an invalid signal number, id, mask, capacity, or environment name.
    case InvalidInput
    # Host data or file content was malformed, such as an environment file that does not parse or is not valid UTF-8.
    case InvalidData
    # An environment file is larger than `max_bytes`.
    case LimitExceeded
    # The host reported that a path or user does not exist.
    case NotFound
    # The host reported that the target already exists.
    case AlreadyExists
    # The host refused the operation for lack of privilege.
    case PermissionDenied
    # The platform does not provide the operation, or a value is not valid UTF-8.
    case Unsupported
    # A signal stream was closed while waiting or before the call.
    case Closed
    # The host reported another failure while performing the operation.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name paths.
        message: String
    )

impl Error for ProcessError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `process: <reason>`.
    fn message() -> String:

impl Error for CommandError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `command: <reason>`, such as `command: operation timed out`.
    fn message() -> String:

# Returns child-process operations for the current host.
export fn commands() -> Commands:

# Returns controls and process information for the current process.
export fn control() -> ProcessControl:

# documentation documentation/standard-library/process.md
# +++
# title = "Commands and processes"
# weight = 12
# +++
#
# # Commands and processes
#
# API reference: [process](reference/process.md) and [io](reference/io.md).
#
# Use stream helpers for bounded reads and copies, and Commands for buffered or long-lived subprocess execution. The caller supplies the streams or command service. Helpers do not acquire authority or close the streams for you.
#
# ## Running commands
#
# The bounded subprocess facility is exported by `@std/process.ms`. Import `commands() -> Commands` from `@std/process.ms` to obtain the host command service:
#
# `Commands.run` and `CommandOutput` are declared in the [`@std/process.ms` reference](reference/process.md).
#
# Omit `input` for empty standard input; `commands().run(program: "tool", arguments: [])` evaluates fresh empty bytes on each call. Supplied bytes are passed unchanged. The same default works through a stored method or a source implementation of `Commands`.
#
# `CommandError` has `InvalidInput`, `Unavailable`, `Timeout`, `OutputLimit`, and `Failed(message: String)`. Empty/NUL program names, NUL arguments, negative bounds, and negative timeout return InvalidInput. The total stdout plus stderr bound is nonnegative. Nonzero ordinary exit is an `ok` output with that code. Timeout or output overflow stops and joins the process before returning its error; caller cancellation unwinds after joining. POSIX process groups include descendants in termination.
#
# On platforms without process-group support the wrapper controls the direct process, with bounded pipe completion; descendant supervision needs a platform host contract. [Managed subprocesses](#managed-subprocesses) cover interactive streams; [network sockets](network.md), [streaming HTTP](http.md) and [WebSockets](websocket.md) are implemented.
#
# ## Stream helpers
#
# These helpers use shared stream views without closing them. Keep the streams' own cleanup scopes open for the whole call. All helpers cooperate with cancellation and enforce cumulative byte limits.
#
# | Helper | Behavior |
# | --- | --- |
# | `copy` | Returns the number of bytes copied. An error may occur after a prefix was written; there is no rollback. |
# | `read_all` | Returns all bytes only on success. |
# | `read_line` | Reads through LF, strips it and a preceding CR, and accepts a final line without a terminator. Native streams buffer read-ahead and retain the remainder for subsequent line or chunk reads after a successful line; source-defined streams read one byte at a time. |
#
# `read_line` returns `none` only if EOF occurs before any data. Its positive `max_bytes` includes terminator bytes. Invalid UTF-8 returns `InvalidData`; overflow returns `LimitExceeded` and may consume data already fetched, including a native read-ahead chunk. A line budget does not reduce the native chunk size or guarantee that overflow preserves the next line. Copy and read_all allow a zero limit for an empty source.
#
# Source streams must return nonempty chunks within the requested size. A malformed stream implementation causes `Failed`.
#
# Expected stream failures preserve their original `IoError` case and payload. Invalid UTF-8 returns `IoError.InvalidData`; an exceeded byte bound returns `IoError.LimitExceeded`. Helpers do not flatten Result or catch cancellation and faults. Convert a File view explicitly to ReadStream when required by the contract-view rules.
#
# ## Managed subprocesses
#
# `commands().spawn(program, arguments)` starts a long-lived child and returns `Result[Subprocess, CommandError]`. Acquire it with `with` so scope exit, return, error, and cancellation close it:
#
# ```manuscript
# import {commands} from "@std/process.ms"
# import {read_line} from "@std/io.ms"
# import panic from "@std/faults.ms"
#
# fn echo_once() -> Unit:
#     match commands().spawn(program: "cat", arguments: []):
#         error(cause): return panic(message: "spawn failed")
#         ok(child):
#             with running = child:
#                 running.stdin().write("ping\n".to_bytes())
#                 running.stdin().close()
#                 read_line(input: running.stdout())
# ```
#
# `Subprocess` exposes `stdin()`, `stdout()`, `stderr()` (shared `WriteStream`/`ReadStream` views of OS pipes), `wait(timeout)`, `terminate()`, `kill()`, and `close()`. Pipes give natural backpressure: a full pipe blocks the writer, and unread output blocks the child, so nothing is buffered without bound. Closing `stdin()` delivers EOF to the child.
#
# - `wait` returns the exit code (`-1` if a signal ended the child). `timeout` expires with `TimedOut` and leaves the child running; caller cancellation unwinds without killing it, because scope exit does that. After exit, `wait` keeps returning the recorded status, including after `close`.
# - `terminate` sends SIGTERM to the process group and `kill` sends SIGKILL; neither waits. Windows has no SIGTERM, so `terminate` kills the direct process.
# - `close` is idempotent. It kills the process group, joins the child, kills any descendants still in the group, and closes all three streams. Unread output is discarded and later stream operations return `Closed`. Cancelling the acquiring execution also kills the group. Aliases to the streams or `Subprocess` do not extend the lifetime.
# - Races: stream EOF can arrive before or after exit (descendants may keep a pipe open), so `wait` is the authority on exit. Output written before exit stays readable until `close`. A read or write blocked when `close` runs returns `Closed`.
# - Readiness is observed by reading `stdout()` or `stderr()` (for example `read_line` until a ready line); no sleep polling is needed.
#
# POSIX hosts place the child in its own process group, so descendants are cleaned up. Other platforms supervise only the direct process. Environment, working-directory, and pseudo-terminal controls are not part of this contract.
#
# ## Current process control
#
# Import `control()` from `@std/process.ms` to query or change the current process. Its [reference](reference/process.md) lists directory, environment, identity, resource, and signal operations. Directory and environment changes affect subsequent host calls.
#
# | View | Contract |
# | --- | --- |
# | `cli.arguments()` | Host-supplied startup tail, excluding the executable; test roots supply an empty list. |
# | `ProcessInfo.arguments` | Native `os.Args` read by `info()`, including `argv[0]`; it is not the CLI accessor's supplied tail. |
# | `cli.environment()` | Startup map retained by the execution's host roots. Repeated calls return the same mutable map. |
# | `System.environment(name)` | Live OS lookup; absent or non-UTF-8 values return `none`. |
# | `ProcessControl.environment()` | Fresh live OS map; non-UTF-8 entries return `ProcessError.Unsupported`. |
# | `set_environment` / `load_environment` | Mutate the live process environment. They do not refresh the CLI map. |
# | `System.working_directory()` | Live cwd on CLI roots, fixed base on a host constructed with a directory; an OS failure faults. |
# | `ProcessControl.working_directory()` | Live cwd query whose failures are `ProcessError` values. |
#
# The CLI list/map can be changed through ordinary collection mutation; that changes the retained view, not native argv or environment. Clone them when a separate snapshot is required. Directory/environment mutation is process-wide, so concurrent operations can observe changes.
#
# `memory_usage` reports the runtime heap and resident-process memory. `load_environment` accepts an optional `export` prefix, quoted multiline values, and comments outside quotes. It validates every entry before writing; existing variables win. `umask` accepts `0..511` (`0777`) and returns the previous mask. `set_identity` accepts exactly the case-sensitive strings `uid`, `gid`, `euid`, and `egid`, with IDs in `0..2147483647`; other input returns `InvalidInput`. Identity, permission, and priority changes are subject to OS policy.
#
# Linux and macOS support process resource accounting, identities, groups, and umask. Windows supports resource accounting, console titles, and native priority classes; identity/group/umask changes and executable replacement return `Unsupported`.
#
# ## Process time and accounting
#
# `uptime()` is a Duration measured since native runtime initialization. `monotonic_time()` is the same elapsed span as an Int in **nanoseconds**, with the same runtime-initialization origin. It is not a Unix timestamp, CPU time, or an Instant from a Clock. `SystemMetrics.uptime` instead measures host boot uptime, at whole-second native resolution. Prefer `clock().now()` and `Instant.difference` for elapsed measurements; see [time values](system.md#time-value-methods).
#
# `CpuUsage.user_microseconds`/`system_microseconds` and the corresponding ResourceUsage fields are cumulative process CPU microseconds. `max_resident_bytes` is peak resident memory in bytes. Fault, filesystem-I/O and context-switch fields are counts: Unix filesystem counters count block I/O, while Windows counters count I/O operations and unavailable fault/context-switch fields are zero. MemoryUsage fields and constrained/available memory are bytes. Host CpuInfo counters use milliseconds, and speed_mhz is integer MHz.
#
# ## Signals
#
# `watch_signals` returns a scoped `SignalStream` with a bounded delivery buffer. The signal list must be nonempty; numbers must be `1..64`, excluding SIGKILL and SIGSTOP. A supplied capacity must be `1..1048576` (omission/`none` uses 128). Range validation does not guarantee that every number denotes a supported signal on every OS. Use `system.constants()` and handle absent names. OS signal delivery can coalesce or drop repeated signals; SIGKILL and SIGSTOP cannot be observed. The native host still treats SIGINT/SIGTERM as cancellation. A watcher only observes; it cannot claim a signal or protect code after `next()`. Use registered `with`/`Closeable` cleanup for shutdown, and finish required writes directly in the shielded close call after joining cancelled workers. See the [shutdown cookbook](../concurrency/shutdown.md) for runnable examples and limitations. `send_signal` validates a signed 32-bit PID and signal `0..64`; the native OS decides whether the selected number/target is supported. Unix `send_signal` accepts signed PIDs for process groups and signal zero for existence checks. Windows supports existence checks and forced termination for its INT/KILL/TERM mapping; other signals return `Unsupported`.
#
# ## Titles, memory, and replacement
#
# Process titles use Linux kernel names (at most 15 UTF-8 bytes), macOS program names, or Windows console titles. They do not rewrite argv. Linux constrained-memory queries inspect the current cgroup v1/v2 memory controller; zero means no known limit. Available memory is the lesser of host available memory and the remaining known cgroup budget. On other hosts, constrained memory is zero (unknown), and available memory uses the native host query. `initialize_groups` resolves a user's supplementary groups and applies them under native privilege checks. Unix `replace` supplies an explicit argv and environment and replaces the executable; success never returns and bypasses scoped cleanup, just as native exec does. Use ordinary `Commands.run` when the caller must retain its execution lifetime.
# end-documentation

# documentation documentation/concurrency/shutdown.md
# +++
# title = "Shutdown on SIGINT and SIGTERM"
# weight = 8
# +++
#
# # Shutdown on SIGINT and SIGTERM
#
# Put shutdown work in a `Closeable.close()` registered by `with`. The native application host requests cancellation on SIGINT or SIGTERM, unwinds registered scopes, and waits for cleanup and joined work. `ms run` forwards those signals and waits for the native application. Successful cleanup still exits 130 for SIGINT or 143 for SIGTERM.
#
# ## Observing a signal does not claim it
#
# `control().watch_signals()` creates an observer. It does not acknowledge, claim, or suppress host cancellation. `SignalStream.next()` is cancellable; cancellation unwinds instead of returning a `ProcessError`. Signal delivery and host cancellation run independently. `next()` can deliver before cancellation reaches it, but code following that delivery has no protected interval in which to finish.
#
# Save this example as `observe.ms`, build it with `ms build observe.ms -o observe`, and send SIGTERM to that disposable program after it prints `waiting`:
#
# <!-- manuscript-example: {"mode":"signal","name":"observer"} -->
# ```manuscript
# import stdout from "@std/io.ms"
# import control from "@std/process.ms"
# import sleep from "@std/time.ms"
#
# export fn main() -> Int:
#     match control().watch_signals(signals: [2, 15]):
#         error(_):
#             return 1
#         ok(signals):
#             with signals = signals:
#                 stdout().write(data: "waiting\n".to_bytes())
#                 let observed = signals.next()
#                 stdout().write(data: "got signal\n".to_bytes())
#                 sleep(duration: 100.milliseconds)
#                 stdout().write(data: "after sleep\n".to_bytes())
#                 return 0
# ```
#
# ```sh
# ./observe > observe.log &
# pid=$!
# # Wait until observe.log contains "waiting", then:
# kill -TERM "$pid"
# wait "$pid"   # status 143
# cat observe.log
# ```
#
# `got signal` may appear or be skipped. `sleep`, writes, locks, and other cancellation checkpoints can unwind before the next statement runs. Neither observing the signal nor returning a normal status overrides cancellation once the host accepts it. Do not use the code after `next()` as a shutdown callback. Observers are useful for signals that the host does not treat as stop requests, subject to platform support and lossy OS delivery.
#
# ## Close the server under the cleanup shield
#
# Registered cleanup ignores the cancellation that initiated unwinding. Calls made directly from `close()` use that shield too: they may suspend, acquire a lock, or perform bounded socket I/O. Here “synchronous shutdown” means doing and finishing the work in the close call, not requiring nonblocking operations.
#
# The shield does not change existing workers' execution parents. Workers in a `TaskGroup` constructed under `main` are cancelled with `main`; they may already have stopped when server cleanup starts. `TaskGroup.close()` cancels unfinished workers and joins their cleanup. It does not drain their ordinary bodies. Likewise, a Scheduler's drain setting cannot revive work cancelled through its construction parent.
#
# This deliberately small server accepts one client. It registers dependencies outside the server scope, joins its worker before using the connection for shutdown, writes the farewell directly from `close()`, and closes the connection. The worker's own `with` cleanup prints `worker stopped`; its ordinary farewell after the long sleep is abandoned on cancellation.
#
# Save as `shutdown.ms` and run `ms build shutdown.ms -o shutdown`:
#
# <!-- manuscript-example: {"mode":"signal","name":"server"} -->
# ```manuscript
# import Closeable from "@std/cleanup.ms"
# import stdout from "@std/io.ms"
# import {network, Listener, Connection} from "@std/net.ms"
# import control from "@std/process.ms"
# import {TaskGroup, check_cancelled} from "@std/tasks.ms"
# import sleep from "@std/time.ms"
#
# type WorkerCleanup:
#     label: String
#
# impl Closeable for WorkerCleanup:
#     fn close() -> Unit:
#         stdout().write(data: "{self.label} stopped\n".to_bytes())
#
# type Server:
#     listener: Listener
#     client: Connection
#     workers: TaskGroup
#     closed: Bool = false
#
# impl Closeable for Server:
#     fn close() -> Unit:
#         if self.closed:
#             return
#         self.closed = true
#         self.listener.close()
#         self.workers.close()
#         check_cancelled()
#         sleep(duration: 10.milliseconds)
#         match self.client.write(data: "farewell\n".to_bytes(), timeout: 1.seconds):
#             ok(_):
#                 stdout().write(data: "farewell sent\n".to_bytes())
#             error(cause):
#                 stdout().write(data: "farewell failed: {cause.message()}\n".to_bytes())
#         self.client.close()
#
# fn serve() -> Result[Unit, Error]:
#     with signals = try control().watch_signals(signals: [2, 15]):
#         with listener = try network().listen(address: "127.0.0.1:0"):
#             stdout().write(data: "{listener.address}\n".to_bytes())
#             with client = try listener.accept():
#                 with workers = TaskGroup():
#                     with server = Server(listener: listener, client: client, workers: workers):
#                         workers.start(fn():
#                             with cleanup = WorkerCleanup(label: "worker"):
#                                 stdout().write(data: "ready\n".to_bytes())
#                                 sleep(duration: 3600.seconds)
#                                 client.write(data: "worker farewell\n".to_bytes())
#                                 return unit
#                         )
#                         let observed = signals.next()
#                         return ok(unit)
#
# export fn main() -> Int:
#     match serve():
#         ok(_):
#             return 0
#         error(cause):
#             stdout().write(data: "{cause.message()}\n".to_bytes())
#             return 1
# ```
#
# Start `./shutdown`, connect a TCP client to the printed loopback address (for example `nc 127.0.0.1 <port>`), and wait for `ready`. From another terminal send `kill -TERM <shutdown-pid>`. The client receives `farewell` and then EOF; the server prints `worker stopped` followed by `farewell sent` and exits 143. SIGINT gives the same cleanup with status 130. The repository integration test executes these exact code fences for both signals, directly and through `ms run`.
#
# For several clients or queued messages, keep pending data in application-owned state, stop admission, join workers, and drain the remaining data directly in `close()` while sockets are still open. Protect shared state with one `Synchronized` wrapper and ensure workers release its guards during cleanup. Never hold a guard while joining a worker that needs the same guard. A reference captured by a worker does not keep an outer resource scope open.
#
# ## Limits
#
# - The server example is for POSIX SIGINT/SIGTERM. Windows forced termination through `send_signal` does not provide this graceful path. SIGKILL, process crashes, and external forced termination bypass cleanup.
# - A successful socket write means bytes were accepted by the transport, not that the peer processed them. Peer disconnects and write timeouts remain possible. This example reports an expected farewell error and still closes the socket; an application needing delivery acknowledgement must implement and bound that protocol explicitly.
# - Automatic `close()` returns `Unit`. Handle expected flush failures inside it, or expose a separate Result-returning `finish()` for ordinary operation. An explicit `server.close()` call in already-cancelled ordinary code is itself cancellable; the shield here comes from registered `with` cleanup.
# - Shielding is not a time limit. Bound shutdown I/O explicitly. Joining uncooperative work can still wait indefinitely. The current native `RunMain` has no cleanup watchdog or second-signal escalation; do not rely on the host-escalation policy described for runtime implementers as an implemented CLI deadline.
# - There is no signal-claiming API, public cancellation catch/shield block, or reparenting API that lets existing workers continue their normal bodies after host cancellation. A helper with that guarantee requires a separate lifetime/API decision. The cookbook preserves the existing observation and lifetime rules.
#
# See [cancellation checkpoints](cancellation.md#propagation-and-checkpoints), [cleanup order](../core-language/cleanup/exit-order.md), and [process signals](../standard-library/process.md#signals).
# end-documentation
