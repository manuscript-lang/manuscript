# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"
import ReadStream from "@std/io.ms"
import WriteStream from "@std/io.ms"

# Errors returned when a process cannot start, times out, or exceeds an output bound.
export type CommandError:
    case InvalidInput
    case Unavailable
    case TimedOut
    case OutputLimit
    case Failed(message: String)

# Captured exit status and standard output/error from a completed command.
export type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes

# Runs child programs with explicit input, output bounds, and an optional timeout.
export interface Commands:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[CommandOutput, CommandError]
    fn spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]

# A long-lived child process with live stdin, stdout, and stderr pipes. Closing it
# kills the child's process group, joins it, and closes all three streams.
export interface Subprocess:
    fn stdin() -> WriteStream
    fn stdout() -> ReadStream
    fn stderr() -> ReadStream
    fn wait(timeout: Optional[Duration] = none) -> Result[Int, CommandError]
    fn terminate() -> Unit
    fn kill() -> Unit
    fn close() -> Unit

# Process and operating-system controls for the current process.
export interface ProcessControl:
    fn monotonic_time() -> Int
    fn watch_signals(
        signals: List[Int],
        capacity: Optional[Int] = none
    ) -> Result[SignalStream, ProcessError]
    fn constrained_memory() -> Result[Int, ProcessError]
    fn available_memory() -> Result[Int, ProcessError]
    fn title() -> Result[String, ProcessError]
    fn set_title(title: String) -> Result[Unit, ProcessError]
    fn initialize_groups(username: String, gid: Int) -> Result[Unit, ProcessError]
    fn replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) -> Result[Unit, ProcessError]
    fn info() -> Result[ProcessInfo, ProcessError]
    fn memory_usage() -> Result[MemoryUsage, ProcessError]
    fn cpu_usage() -> Result[CpuUsage, ProcessError]
    fn uptime() -> Result[Duration, ProcessError]
    fn environment() -> Result[Map[String, String], ProcessError]
    fn set_environment(
        name: String,
        value: Optional[String]
    ) -> Result[Unit, ProcessError]
    fn load_environment(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, ProcessError]
    fn working_directory() -> Result[String, ProcessError]
    fn change_directory(path: String) -> Result[Unit, ProcessError]
    fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
    fn groups() -> Result[List[Int], ProcessError]
    fn resource_usage() -> Result[ResourceUsage, ProcessError]
    fn umask(mask: Int) -> Result[Int, ProcessError]
    fn set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
    fn set_groups(groups: List[Int]) -> Result[Unit, ProcessError]

# Identity and invocation details for the current process.
export type ProcessInfo:
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

# Memory statistics for the current process.
export type MemoryUsage:
    heap_used: Int
    heap_total: Int
    heap_system: Int
    external: Int
    resident: Int

# CPU time consumed by the current process.
export type CpuUsage:
    user_microseconds: Int
    system_microseconds: Int

# Kernel resource counters for the current process.
export type ResourceUsage:
    user_microseconds: Int
    system_microseconds: Int
    max_resident_bytes: Int
    minor_faults: Int
    major_faults: Int
    filesystem_reads: Int
    filesystem_writes: Int
    voluntary_switches: Int
    involuntary_switches: Int

# A stream of operating-system signals selected by `watch_signals`.
export interface SignalStream:
    fn close() -> Unit
    fn next() -> Result[Int, ProcessError]

# Errors returned by process-control operations.
export type ProcessError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)

impl Error for ProcessError:
    fn message() -> String:

impl Error for CommandError:
    fn message() -> String:

# Returns child-process operations for the current host.
export fn commands() -> Commands:

# Returns controls and process information for the current process.
export fn control() -> ProcessControl:
