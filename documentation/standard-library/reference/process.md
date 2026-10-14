+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError {data-api-kind="Alternative"}

Errors returned when a process cannot start, times out, or exceeds an output bound.

```manuscript
type CommandError:
    case InvalidInput
    case Unavailable
    case Timeout
    case OutputLimit
    case Failed(message: String)
```

```manuscript
impl Error for CommandError:
    fn message() -> String:
```

### CommandError.Failed

The command could not be started or run for another reason reported by the host.

```manuscript
case Failed(message: String)
```

### CommandError.InvalidInput

The program name is empty, or the program, an argument, or a limit holds a NUL byte or is negative.

```manuscript
case InvalidInput
```

### CommandError.OutputLimit

The combined standard output and error exceeded `max_output_bytes`, and the command was killed.

```manuscript
case OutputLimit
```

### CommandError.Timeout

The command was still running when `timeout` elapsed, and its process group was killed.

```manuscript
case Timeout
```

### CommandError.Unavailable

The program could not be found or executed, such as a missing executable.

```manuscript
case Unavailable
```

### CommandError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name paths.

```manuscript
message: String
```

### CommandError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `command: <reason>`, such as `command: operation timed out`.

```manuscript
fn message() -> String:
```

## CommandOutput {data-api-kind="Record"}

Captured exit status and standard output/error from a completed command.

```manuscript
type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes
```

### CommandOutput.exit_code

The child's exit status; 0 conventionally means success. A nonzero status is still an Ok result, and a child ended by a signal reports -1 on Unix.

```manuscript
exit_code: Int
```

### CommandOutput.stderr

Everything the child wrote to standard error, as raw bytes that may not be valid UTF-8.

```manuscript
stderr: Bytes
```

### CommandOutput.stdout

Everything the child wrote to standard output, as raw bytes that may not be valid UTF-8.

```manuscript
stdout: Bytes
```

## Commands {data-api-kind="Interface"}

Runs child programs with empty input by default, optional output bounds and timeout.

```manuscript
interface Commands:
    fn run(program: String, arguments: List[String], input: Bytes = "".to_bytes(), max_output_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[CommandOutput, CommandError]
```

### Commands.run

Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
Output beyond `max_output_bytes` in total across both streams returns OutputLimit, `timeout` returns Timeout, and in both cases the child's process group is killed. Cancelling the calling task also kills it.

```manuscript
fn run(program: String, arguments: List[String], input: Bytes = "".to_bytes(), max_output_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[CommandOutput, CommandError]
```

## CpuUsage {data-api-kind="Record"}

Cumulative CPU time consumed by the current process, in integer microseconds.

```manuscript
type CpuUsage:
    user_microseconds: Int
    system_microseconds: Int
```

### CpuUsage.system_microseconds

Kernel CPU time in microseconds.

```manuscript
system_microseconds: Int
```

### CpuUsage.user_microseconds

User CPU time in microseconds.

```manuscript
user_microseconds: Int
```

## MemoryUsage {data-api-kind="Record"}

Memory statistics for the current process; every field is bytes.

```manuscript
type MemoryUsage:
    heap_used: Int
    heap_total: Int
    heap_system: Int
    external: Int
    resident: Int
```

### MemoryUsage.external

Bytes the runtime obtained from the operating system outside the heap, such as stacks and internal tables.

```manuscript
external: Int
```

### MemoryUsage.heap_system

Bytes of heap memory obtained from the operating system, including idle spans.

```manuscript
heap_system: Int
```

### MemoryUsage.heap_total

Bytes of heap spans currently in use, which is at least `heap_used`.

```manuscript
heap_total: Int
```

### MemoryUsage.heap_used

Bytes of heap memory occupied by live objects and objects not yet collected.

```manuscript
heap_used: Int
```

### MemoryUsage.resident

Bytes of physical memory the operating system reports as resident for the process.

```manuscript
resident: Int
```

## ProcessControl {data-api-kind="Interface"}

Process and operating-system controls for the current process.
`watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
`next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup
and finish shutdown work directly in the shielded close call after joining cancelled workers.

```manuscript
interface ProcessControl:
    fn monotonic_time() -> Int
    fn watch_signals(signals: List[Int], capacity: Optional[Int] = none) -> Result[SignalStream, ProcessError]
    fn constrained_memory() -> Result[Int, ProcessError]
    fn available_memory() -> Result[Int, ProcessError]
    fn title() -> Result[String, ProcessError]
    fn set_title(title: String) -> Result[Unit, ProcessError]
    fn initialize_groups(username: String, gid: Int) -> Result[Unit, ProcessError]
    fn replace(program: String, arguments: List[String], environment: Map[String, String]) -> Result[Unit, ProcessError]
    fn info() -> Result[ProcessInfo, ProcessError]
    fn memory_usage() -> Result[MemoryUsage, ProcessError]
    fn cpu_usage() -> Result[CpuUsage, ProcessError]
    fn uptime() -> Result[Duration, ProcessError]
    fn environment() -> Result[Map[String, String], ProcessError]
    fn set_environment(name: String, value: Optional[String]) -> Result[Unit, ProcessError]
    fn load_environment(path: String, max_bytes: Optional[Int] = none) -> Result[Unit, ProcessError]
    fn working_directory() -> Result[String, ProcessError]
    fn change_directory(path: String) -> Result[Unit, ProcessError]
    fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
    fn groups() -> Result[List[Int], ProcessError]
    fn resource_usage() -> Result[ResourceUsage, ProcessError]
    fn umask(mask: Int) -> Result[Int, ProcessError]
    fn set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
    fn set_groups(groups: List[Int]) -> Result[Unit, ProcessError]
```

### ProcessControl.available_memory

Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.

```manuscript
fn available_memory() -> Result[Int, ProcessError]
```

### ProcessControl.change_directory

Changes the working directory of the whole process, affecting relative paths everywhere.
A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.

```manuscript
fn change_directory(path: String) -> Result[Unit, ProcessError]
```

### ProcessControl.constrained_memory

Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.

```manuscript
fn constrained_memory() -> Result[Int, ProcessError]
```

### ProcessControl.cpu_usage

Returns cumulative user and kernel CPU time consumed by this process in microseconds.
Platforms without resource accounting return Unsupported.

```manuscript
fn cpu_usage() -> Result[CpuUsage, ProcessError]
```

### ProcessControl.environment

Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.

```manuscript
fn environment() -> Result[Map[String, String], ProcessError]
```

### ProcessControl.groups

Returns the numeric ids of the supplementary groups of the process.
Windows returns Unsupported.

```manuscript
fn groups() -> Result[List[Int], ProcessError]
```

### ProcessControl.info

Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
Text that is not valid UTF-8 returns Unsupported.

```manuscript
fn info() -> Result[ProcessInfo, ProcessError]
```

### ProcessControl.initialize_groups

Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.

```manuscript
fn initialize_groups(username: String, gid: Int) -> Result[Unit, ProcessError]
```

### ProcessControl.load_environment

Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.

```manuscript
fn load_environment(path: String, max_bytes: Optional[Int] = none) -> Result[Unit, ProcessError]
```

### ProcessControl.memory_usage

Returns heap and resident memory statistics for this process, in bytes.

```manuscript
fn memory_usage() -> Result[MemoryUsage, ProcessError]
```

### ProcessControl.monotonic_time

Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.

```manuscript
fn monotonic_time() -> Int
```

### ProcessControl.replace

Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
`program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.

```manuscript
fn replace(program: String, arguments: List[String], environment: Map[String, String]) -> Result[Unit, ProcessError]
```

### ProcessControl.resource_usage

Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
Platforms without them return Unsupported.

```manuscript
fn resource_usage() -> Result[ResourceUsage, ProcessError]
```

### ProcessControl.send_signal

Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.

```manuscript
fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
```

### ProcessControl.set_environment

Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.

```manuscript
fn set_environment(name: String, value: Optional[String]) -> Result[Unit, ProcessError]
```

### ProcessControl.set_groups

Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.

```manuscript
fn set_groups(groups: List[Int]) -> Result[Unit, ProcessError]
```

### ProcessControl.set_identity

Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
Identity changes require OS permission and are Unsupported on Windows.

```manuscript
fn set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
```

### ProcessControl.set_title

Sets the process title shown by tools such as `ps`.
A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.

```manuscript
fn set_title(title: String) -> Result[Unit, ProcessError]
```

### ProcessControl.title

Returns the current process title.
Platforms that cannot read it return Unsupported.

```manuscript
fn title() -> Result[String, ProcessError]
```

### ProcessControl.umask

Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.

```manuscript
fn umask(mask: Int) -> Result[Int, ProcessError]
```

### ProcessControl.uptime

Returns elapsed Duration since runtime initialization, rather than host boot.

```manuscript
fn uptime() -> Result[Duration, ProcessError]
```

### ProcessControl.watch_signals

Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
Capacity must be 1..1048576; omission/none uses 128 buffered signals.
Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.

```manuscript
fn watch_signals(signals: List[Int], capacity: Optional[Int] = none) -> Result[SignalStream, ProcessError]
```

### ProcessControl.working_directory

Reads the live process directory, preserving OS failures as ProcessError.

```manuscript
fn working_directory() -> Result[String, ProcessError]
```

See the [shutdown cookbook](../../concurrency/shutdown.md) for runnable examples and limitations.

## ProcessError {data-api-kind="Alternative"}

Errors returned by process-control operations.

```manuscript
type ProcessError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)
```

```manuscript
impl Error for ProcessError:
    fn message() -> String:
```

### ProcessError.AlreadyExists

The host reported that the target already exists.

```manuscript
case AlreadyExists
```

### ProcessError.Closed

A signal stream was closed while waiting or before the call.

```manuscript
case Closed
```

### ProcessError.Failed

The host reported another failure while performing the operation.

```manuscript
case Failed(message: String)
```

### ProcessError.InvalidData

Host data or file content was malformed, such as an environment file that does not parse or is not valid UTF-8.

```manuscript
case InvalidData
```

### ProcessError.InvalidInput

An argument is outside its documented range or contains NUL, such as an invalid signal number, id, mask, capacity, or environment name.

```manuscript
case InvalidInput
```

### ProcessError.LimitExceeded

An environment file is larger than `max_bytes`.

```manuscript
case LimitExceeded
```

### ProcessError.NotFound

The host reported that a path or user does not exist.

```manuscript
case NotFound
```

### ProcessError.PermissionDenied

The host refused the operation for lack of privilege.

```manuscript
case PermissionDenied
```

### ProcessError.Unsupported

The platform does not provide the operation, or a value is not valid UTF-8.

```manuscript
case Unsupported
```

### ProcessError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name paths.

```manuscript
message: String
```

### ProcessError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `process: <reason>`.

```manuscript
fn message() -> String:
```

## ProcessInfo {data-api-kind="Record"}

Identity and invocation details for the current process.

```manuscript
type ProcessInfo:
    pid: Int
    parent_pid: Int
    executable: String
    arguments: List[String]
    os: String
    architecture: String
    uid: Int
    gid: Int
    effective_uid: Int
    effective_gid: Int
```

### ProcessInfo.architecture

Processor architecture in Go's naming, such as `amd64` or `arm64`.

```manuscript
architecture: String
```

### ProcessInfo.arguments

Live native argv including argv[0]; cli.arguments() is the supplied startup tail without it.

```manuscript
arguments: List[String]
```

### ProcessInfo.effective_gid

Effective group id used for permission checks; -1 on Windows.

```manuscript
effective_gid: Int
```

### ProcessInfo.effective_uid

Effective user id used for permission checks; -1 on Windows.

```manuscript
effective_uid: Int
```

### ProcessInfo.executable

Absolute path of the running program file.

```manuscript
executable: String
```

### ProcessInfo.gid

Real group id; -1 on Windows, where ids are not numeric.

```manuscript
gid: Int
```

### ProcessInfo.os

Operating system name in Go's naming, such as `linux`, `darwin`, or `windows`.

```manuscript
os: String
```

### ProcessInfo.parent_pid

Operating system id of the parent process at the time of the call.

```manuscript
parent_pid: Int
```

### ProcessInfo.pid

Operating system id of this process.

```manuscript
pid: Int
```

### ProcessInfo.uid

Real user id; -1 on Windows, where ids are not numeric.

```manuscript
uid: Int
```

## ResourceUsage {data-api-kind="Record"}

Kernel resource counters for the current process. CPU times are integer microseconds;
max_resident_bytes is bytes; other fields are counts, not durations or byte totals.
Filesystem reads/writes count native block I/O on Unix and I/O operations on Windows.
Unavailable Windows fault/context-switch counters are zero.

```manuscript
type ResourceUsage:
    user_microseconds: Int
    system_microseconds: Int
    max_resident_bytes: Int
    minor_faults: Int
    major_faults: Int
    filesystem_reads: Int
    filesystem_writes: Int
    voluntary_switches: Int
    involuntary_switches: Int
```

### ResourceUsage.filesystem_reads

Block input operations charged to the process, as a count.

```manuscript
filesystem_reads: Int
```

### ResourceUsage.filesystem_writes

Block output operations charged to the process, as a count.

```manuscript
filesystem_writes: Int
```

### ResourceUsage.involuntary_switches

Context switches where the scheduler preempted the process, as a count.

```manuscript
involuntary_switches: Int
```

### ResourceUsage.major_faults

Page faults that required disk I/O, as a count.

```manuscript
major_faults: Int
```

### ResourceUsage.max_resident_bytes

Peak physical memory the process has held at once, in bytes.

```manuscript
max_resident_bytes: Int
```

### ResourceUsage.minor_faults

Page faults served without disk I/O, as a count.

```manuscript
minor_faults: Int
```

### ResourceUsage.system_microseconds

Cumulative CPU time the kernel spent on behalf of this process, in microseconds.

```manuscript
system_microseconds: Int
```

### ResourceUsage.user_microseconds

Cumulative CPU time spent running this process's own code, in microseconds.

```manuscript
user_microseconds: Int
```

### ResourceUsage.voluntary_switches

Context switches where the process gave up the CPU, such as to wait for I/O, as a count.

```manuscript
voluntary_switches: Int
```

## SignalStream {data-api-kind="Interface"}

A cancellable observer of operating-system signals selected by `watch_signals`.
SIGINT/SIGTERM still cancel the native application; `close()` unregisters this observer.
`next()` and following code have no shutdown guarantee; use registered `with`/`Closeable` cleanup.

```manuscript
interface SignalStream:
    fn close() -> Unit
    fn next() -> Result[Int, ProcessError]
```

### SignalStream.close

Stops observing signals, wakes a pending `next` with Closed, and waits for it.
Safe to call repeatedly.

```manuscript
fn close() -> Unit
```

### SignalStream.next

Waits for the next observed signal and returns its number. Signals arriving while no call waits are buffered up to the stream's capacity.
Returns Closed after `close`. Cancelling the waiting task unwinds it.

```manuscript
fn next() -> Result[Int, ProcessError]
```

See the [shutdown cookbook](../../concurrency/shutdown.md) for runnable examples and limitations.

## commands {data-api-kind="Function"}

Returns child-process operations for the current host.

```manuscript
fn commands() -> Commands:
```

## control {data-api-kind="Function"}

Returns controls and process information for the current process.

```manuscript
fn control() -> ProcessControl:
```

