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
    ) Result[CommandOutput, CommandError]
    # Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess for use with `with`. `arguments` follow the program name; stdin, stdout, and stderr are OS pipes. Returns InvalidInput, Unavailable, or Failed when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
    fn spawn(program: String, arguments: List[String]) Result[Subprocess, CommandError]

# A long-lived child process with live stdin, stdout, and stderr pipes. Closing it
# kills the child's process group, joins it, and closes all three streams.
export interface Subprocess:
    # The child's standard input as a WriteStream; writes block when the pipe is full. Closing the stream delivers end-of-input to the child.
    fn stdin() WriteStream
    # The child's standard output as a ReadStream over the OS pipe; reads block until output or end-of-file, and nothing is buffered without bound.
    fn stdout() ReadStream
    # The child's standard error as a ReadStream over the OS pipe, with the same blocking and backpressure behavior as stdout.
    fn stderr() ReadStream
    # Waits for the child to exit and returns its exit status. Returns Timeout if `timeout` elapses first, leaving the child running.
    fn wait(timeout: Optional[Duration] = none) Result[Int, CommandError]
    # Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it kills the direct process. Does not wait.
    fn terminate() Unit
    # Sends SIGKILL to the child's process group. Does not wait.
    fn kill() Unit
    # Kills the process group, joins the child, kills leftover group members, and closes all three streams. Idempotent; `with` calls it on scope exit.
    fn close() Unit

# Process and operating-system controls for the current process.
# `watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
# `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup
# and finish shutdown work directly in the shielded close call after joining cancelled workers.
export interface ProcessControl:
    # Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
    # This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.
    fn monotonic_time() Int
    # Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
    # Capacity must be 1..1048576; omission/none uses 128 buffered signals.
    # Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
    # Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
    fn watch_signals(
        signals: List[Int],
        capacity: Optional[Int] = none
    ) Result[SignalStream, ProcessError]
    # Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
    fn constrained_memory() Result[Int, ProcessError]
    # Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
    fn available_memory() Result[Int, ProcessError]
    # Returns the current process title.
    # Platforms that cannot read it return Unsupported.
    fn title() Result[String, ProcessError]
    # Sets the process title shown by tools such as `ps`.
    # A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.
    fn set_title(title: String) Result[Unit, ProcessError]
    # Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
    # A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.
    fn initialize_groups(username: String, gid: Int) Result[Unit, ProcessError]
    # Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
    # `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.
    fn replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) Result[Unit, ProcessError]
    # Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
    # Text that is not valid UTF-8 returns Unsupported.
    fn info() Result[ProcessInfo, ProcessError]
    # Returns heap and resident memory statistics for this process, in bytes.
    fn memory_usage() Result[MemoryUsage, ProcessError]
    # Returns cumulative user and kernel CPU time consumed by this process in microseconds.
    # Platforms without resource accounting return Unsupported.
    fn cpu_usage() Result[CpuUsage, ProcessError]
    # Returns elapsed Duration since runtime initialization, rather than host boot.
    fn uptime() Result[Duration, ProcessError]
    # Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
    fn environment() Result[Map[String, String], ProcessError]
    # Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
    # An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.
    fn set_environment(name: String, value: Optional[String]) Result[Unit, ProcessError]
    # Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
    # Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.
    fn load_environment(
        path: String,
        max_bytes: Optional[Int] = none
    ) Result[Unit, ProcessError]
    # Reads the live process directory, preserving OS failures as ProcessError.
    fn working_directory() Result[String, ProcessError]
    # Changes the working directory of the whole process, affecting relative paths everywhere.
    # A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.
    fn change_directory(path: String) Result[Unit, ProcessError]
    # Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
    # Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.
    fn send_signal(pid: Int, signal: Int) Result[Unit, ProcessError]
    # Returns the numeric ids of the supplementary groups of the process.
    # Windows returns Unsupported.
    fn groups() Result[List[Int], ProcessError]
    # Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
    # Platforms without them return Unsupported.
    fn resource_usage() Result[ResourceUsage, ProcessError]
    # Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
    fn umask(mask: Int) Result[Int, ProcessError]
    # Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
    # Identity changes require OS permission and are Unsupported on Windows.
    fn set_identity(kind: String, id: Int) Result[Unit, ProcessError]
    # Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
    # Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.
    fn set_groups(groups: List[Int]) Result[Unit, ProcessError]

# Identity and invocation details for the current process.
export type ProcessInfo:
    # Operating system id of this process.
    pid: Int
    # Operating system id of the parent process at the time of the call.
    parent_pid: Int
    # Absolute path of the running program file.
    executable: String
    # Live native argv including argv[0]; process.arguments() is the supplied startup tail without it.
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
    fn close() Unit
    # Waits for the next observed signal and returns its number. Signals arriving while no call waits are buffered up to the stream's capacity.
    # Returns Closed after `close`. Cancelling the waiting task unwinds it.
    fn next() Result[Int, ProcessError]

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
    fn message() String:

impl Error for CommandError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `command: <reason>`, such as `command: operation timed out`.
    fn message() String:

# Returns child-process operations for the current host.
export fn commands() Commands:

# Returns the host-supplied startup arguments, excluding the executable path.
# Repeated calls share the same mutable list; mutations do not rewrite native argv.
export fn arguments() List[String]:

# Returns controls and process information for the current process.
export fn control() ProcessControl:
