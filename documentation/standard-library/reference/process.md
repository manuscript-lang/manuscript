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
    case TimedOut
    case OutputLimit
    case Failed(message: String)
```

```manuscript
impl Error for CommandError:
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

## Commands {data-api-kind="Interface"}

Runs child programs with empty input by default, optional output bounds and timeout.

```manuscript
interface Commands:
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

### ProcessControl.environment

Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.

```manuscript
fn environment() -> Result[Map[String, String], ProcessError]
```

### ProcessControl.monotonic_time

Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.

```manuscript
fn monotonic_time() -> Int
```

### ProcessControl.send_signal

Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.

```manuscript
fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
```

### ProcessControl.set_identity

Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
Identity changes require OS permission and are Unsupported on Windows.

```manuscript
fn set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
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

### ProcessInfo.arguments

Live native argv including argv[0]; cli.arguments() is the supplied startup tail without it.

```manuscript
arguments: List[String]
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

## SignalStream {data-api-kind="Interface"}

A cancellable observer of operating-system signals selected by `watch_signals`.
SIGINT/SIGTERM still cancel the native application; `close()` unregisters this observer.
`next()` and following code have no shutdown guarantee; use registered `with`/`Closeable` cleanup.

```manuscript
interface SignalStream:
    fn close() -> Unit
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

