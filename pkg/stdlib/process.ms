# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"

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

# Runs child programs with empty input by default, optional output bounds and timeout.
export interface Commands:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = "".to_bytes(),
        max_output_bytes: Optional[Int64] = none,
        timeout: Optional[Duration] = none
    ) -> Result[CommandOutput, CommandError]

# Process and operating-system controls for the current process.
# `watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
# `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup
# and finish shutdown work directly in the shielded close call after joining cancelled workers.
export interface ProcessControl:
    # Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
    # This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.
    fn monotonic_time() -> Int64
    # Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
    # Capacity must be 1..1048576; omission/none uses 128 buffered signals.
    # Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
    # Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
    fn watch_signals(
        signals: List[Int],
        capacity: Optional[Int] = none
    ) -> Result[SignalStream, ProcessError]
    fn constrained_memory() -> Result[Int64, ProcessError]
    fn available_memory() -> Result[Int64, ProcessError]
    fn title() -> Result[String, ProcessError]
    fn set_title(title: String) -> Result[Unit, ProcessError]
    fn initialize_groups(username: String, gid: Int64) -> Result[Unit, ProcessError]
    fn replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) -> Result[Unit, ProcessError]
    fn info() -> Result[ProcessInfo, ProcessError]
    fn memory_usage() -> Result[MemoryUsage, ProcessError]
    fn cpu_usage() -> Result[CpuUsage, ProcessError]
    # Returns elapsed Duration since runtime initialization, rather than host boot.
    fn uptime() -> Result[Duration, ProcessError]
    # Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
    fn environment() -> Result[Map[String, String], ProcessError]
    fn set_environment(
        name: String,
        value: Optional[String]
    ) -> Result[Unit, ProcessError]
    fn load_environment(
        path: String,
        max_bytes: Optional[Int64] = none
    ) -> Result[Unit, ProcessError]
    # Reads the live process directory, preserving OS failures as ProcessError.
    fn working_directory() -> Result[String, ProcessError]
    fn change_directory(path: String) -> Result[Unit, ProcessError]
    # Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
    # Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.
    fn send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
    fn groups() -> Result[List[Int64], ProcessError]
    fn resource_usage() -> Result[ResourceUsage, ProcessError]
    # Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
    fn umask(mask: Int) -> Result[Int, ProcessError]
    # Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
    # Identity changes require OS permission and are Unsupported on Windows.
    fn set_identity(kind: String, id: Int64) -> Result[Unit, ProcessError]
    fn set_groups(groups: List[Int64]) -> Result[Unit, ProcessError]

# Identity and invocation details for the current process.
export type ProcessInfo:
    pid: Int
    parent_pid: Int
    executable: String
    # Live native argv including argv[0]; cli.arguments() is the supplied startup tail without it.
    arguments: List[String]
    os: String
    architecture: String
    uid: Int64
    gid: Int64
    effective_uid: Int64
    effective_gid: Int64

# Memory statistics for the current process; every field is bytes.
export type MemoryUsage:
    heap_used: Int64
    heap_total: Int64
    heap_system: Int64
    external: Int64
    resident: Int64

# Cumulative CPU time consumed by the current process, in integer microseconds.
export type CpuUsage:
    # User CPU time in microseconds.
    user_microseconds: Int64
    # Kernel CPU time in microseconds.
    system_microseconds: Int64

# Kernel resource counters for the current process. CPU times are integer microseconds;
# max_resident_bytes is bytes; other fields are counts, not durations or byte totals.
# Filesystem reads/writes count native block I/O on Unix and I/O operations on Windows.
# Unavailable Windows fault/context-switch counters are zero.
export type ResourceUsage:
    user_microseconds: Int64
    system_microseconds: Int64
    max_resident_bytes: Int64
    minor_faults: Int64
    major_faults: Int64
    filesystem_reads: Int64
    filesystem_writes: Int64
    voluntary_switches: Int64
    involuntary_switches: Int64

# A cancellable observer of operating-system signals selected by `watch_signals`.
# SIGINT/SIGTERM still cancel the native application; `close()` unregisters this observer.
# `next()` and following code have no shutdown guarantee; use registered `with`/`Closeable` cleanup.
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
