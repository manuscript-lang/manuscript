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

Runs child programs with explicit input, output bounds, and an optional timeout.

```manuscript
interface Commands:
    fn run(program: String, arguments: List[String], input: Bytes, max_output_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[CommandOutput, CommandError]
```

## CpuUsage {data-api-kind="Record"}

Cumulative CPU time consumed by the current process, in integer microseconds.

```manuscript
type CpuUsage:
    user_microseconds: Int
    system_microseconds: Int
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

### ProcessControl.watch_signals

Observes signals without claiming them or suppressing host cancellation.
Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.

```manuscript
fn watch_signals(signals: List[Int], capacity: Optional[Int] = none) -> Result[SignalStream, ProcessError]
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

