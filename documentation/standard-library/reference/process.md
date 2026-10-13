+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError {data-api-kind="Alternative"}

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

```manuscript
type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes
```

## Commands {data-api-kind="Interface"}

```manuscript
interface Commands:
    fn run(program: String, arguments: List[String], input: Bytes, max_output_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[CommandOutput, CommandError]
```

## CpuUsage {data-api-kind="Record"}

```manuscript
type CpuUsage:
    user_microseconds: Int
    system_microseconds: Int
```

## MemoryUsage {data-api-kind="Record"}

```manuscript
type MemoryUsage:
    heap_used: Int
    heap_total: Int
    heap_system: Int
    external: Int
    resident: Int
```

## ProcessControl {data-api-kind="Interface"}

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

`watch_signals` observes signals without claiming them. SIGINT/SIGTERM still cancel the native application; `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup and finish shutdown work directly in the shielded close call after joining cancelled workers.

See the [shutdown cookbook](../../concurrency/shutdown.md) for runnable examples and limitations.

## ProcessError {data-api-kind="Alternative"}

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

```manuscript
interface SignalStream:
    fn close() -> Unit
    fn next() -> Result[Int, ProcessError]
```

`watch_signals` observes signals without claiming them. SIGINT/SIGTERM still cancel the native application; `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup and finish shutdown work directly in the shielded close call after joining cancelled workers.

See the [shutdown cookbook](../../concurrency/shutdown.md) for runnable examples and limitations.

## commands {data-api-kind="Function"}

```manuscript
fn commands() -> Commands:
```

## control {data-api-kind="Function"}

```manuscript
fn control() -> ProcessControl:
```

