from "@std/bytes.ms" import Bytes
from "@std/time.ms" import Duration
from "@std/net.ms" import IpFamily
from "@std/io.ms" import ReadStream
from "@std/io.ms" import WriteStream

extern def msstd_process_commands() -> Commands

extern def msrt_args() -> List[String]

extern def msstd_process_control() -> ProcessControl

extern def msstd_system_endianness() -> String

extern def msstd_system_end_of_line() -> String

extern def msstd_system_dev_null() -> String

extern def msstd_system_os_type() -> String

extern def msstd_system_constants() -> Map[String, Int]

extern def msstd_process_system() -> System

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

# Where a child's standard input, output, or error goes, chosen per stream.
# `commands().spawn("make", [], stdout: Stdio.Inherit, stderr: Stdio.Inherit)` lets the child's output reach the parent's terminal while stdin stays piped.
export type Stdio:
    # An OS pipe to the parent, read or written through the Subprocess's stream.
    case Pipe
    # The parent's own stream, so the child reads or writes it directly.
    case Inherit
    # The null device: input is at end of file, output is discarded.
    case Null

# Runs child programs with empty input by default, optional output bounds and timeout.
export interface Commands:
    # Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
    # Output beyond `max_output_bytes` in total across both streams returns OutputLimit, `timeout` returns Timeout, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
    def run(
        program: String,
        arguments: List[String],
        input: Bytes = "".to_bytes(),
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[CommandOutput, CommandError]
    # Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess for use with `with`. `arguments` follow the program name; `stdin`, `stdout`, and `stderr` each choose a pipe (the default), the parent's own stream, or the null device. Returns InvalidInput, Unavailable, or Failed when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
    def spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio = Stdio.Pipe,
        stdout: Stdio = Stdio.Pipe,
        stderr: Stdio = Stdio.Pipe
    ) -> Result[Subprocess, CommandError]

# A long-lived child process with live stdin, stdout, and stderr streams. Closing it
# kills the child's process group, joins it, and closes all three streams.
# A stream spawned as Stdio.Inherit or Stdio.Null has no pipe: it is already closed, so reads and writes return Closed.
export interface Subprocess:
    # The child's standard input as a WriteStream; writes block when the pipe is full. Closing the stream delivers end-of-input to the child.
    def stdin() -> WriteStream
    # The child's standard output as a ReadStream over the OS pipe; reads block until output or end-of-file, and nothing is buffered without bound.
    def stdout() -> ReadStream
    # The child's standard error as a ReadStream over the OS pipe, with the same blocking and backpressure behavior as stdout.
    def stderr() -> ReadStream
    # Waits for the child to exit and returns its exit status. Returns Timeout if `timeout` elapses first, leaving the child running.
    def wait(timeout: Optional[Duration] = none) -> Result[Int, CommandError]
    # Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it kills the direct process. Does not wait.
    def terminate() -> Unit
    # Sends SIGKILL to the child's process group. Does not wait.
    def kill() -> Unit
    # Kills the process group, joins the child, kills leftover group members, and closes all three streams. Idempotent; `with` calls it on scope exit.
    def close() -> Unit

# Process and operating-system controls for the current process.
# `watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
# `next()` and code following it have no shutdown guarantee. Register `with`/`Closeable` cleanup
# and finish shutdown work directly in the shielded close call after joining cancelled workers.
export interface ProcessControl:
    # Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
    # This is not Unix time or a Clock Instant; prefer clock().now().difference(start) for timing.
    def monotonic_time() -> Int
    # Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
    # Capacity must be 1..1048576; omission/none uses 128 buffered signals.
    # Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
    # Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
    def watch_signals(
        signals: List[Int],
        capacity: Optional[Int] = none
    ) -> Result[SignalStream, ProcessError]
    # Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
    def constrained_memory() -> Result[Int, ProcessError]
    # Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
    def available_memory() -> Result[Int, ProcessError]
    # Returns the current process title.
    # Platforms that cannot read it return Unsupported.
    def title() -> Result[String, ProcessError]
    # Sets the process title shown by tools such as `ps`.
    # A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.
    def set_title(title: String) -> Result[Unit, ProcessError]
    # Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
    # A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.
    def initialize_groups(username: String, gid: Int) -> Result[Unit, ProcessError]
    # Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
    # `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.
    def replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) -> Result[Unit, ProcessError]
    # Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
    # Text that is not valid UTF-8 returns Unsupported.
    def info() -> Result[ProcessInfo, ProcessError]
    # Returns heap and resident memory statistics for this process, in bytes.
    def memory_usage() -> Result[MemoryUsage, ProcessError]
    # Returns cumulative user and kernel CPU time consumed by this process in microseconds.
    # Platforms without resource accounting return Unsupported.
    def cpu_usage() -> Result[CpuUsage, ProcessError]
    # Returns elapsed Duration since runtime initialization, rather than host boot.
    def uptime() -> Result[Duration, ProcessError]
    # Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
    def environment() -> Result[Map[String, String], ProcessError]
    # Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
    # An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.
    def set_environment(
        name: String,
        value: Optional[String]
    ) -> Result[Unit, ProcessError]
    # Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
    # Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.
    def load_environment(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, ProcessError]
    # Reads the live process directory, preserving OS failures as ProcessError.
    def working_directory() -> Result[String, ProcessError]
    # Changes the working directory of the whole process, affecting relative paths everywhere.
    # A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.
    def change_directory(path: String) -> Result[Unit, ProcessError]
    # Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
    # Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination.
    def send_signal(pid: Int, signal: Int) -> Result[Unit, ProcessError]
    # Returns the numeric ids of the supplementary groups of the process.
    # Windows returns Unsupported.
    def groups() -> Result[List[Int], ProcessError]
    # Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
    # Platforms without them return Unsupported.
    def resource_usage() -> Result[ResourceUsage, ProcessError]
    # Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
    def umask(mask: Int) -> Result[Int, ProcessError]
    # Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
    # Identity changes require OS permission and are Unsupported on Windows.
    def set_identity(kind: String, id: Int) -> Result[Unit, ProcessError]
    # Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
    # Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.
    def set_groups(groups: List[Int]) -> Result[Unit, ProcessError]

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
    # Operating system name, such as `linux`, `darwin`, or `windows`.
    os: String
    # Processor architecture name, such as `amd64` or `arm64`.
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
    def close() -> Unit
    # Waits for the next observed signal and returns its number. Signals arriving while no call waits are buffered up to the stream's capacity.
    # Returns Closed after `close`. Cancelling the waiting task unwinds it.
    def next() -> Result[Int, ProcessError]

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
    def message() -> String:
        match self:
            case InvalidInput: return "process: invalid input"
            case InvalidData: return "process: invalid data"
            case LimitExceeded: return "process: limit exceeded"
            case NotFound: return "process: not found"
            case AlreadyExists: return "process: already exists"
            case PermissionDenied: return "process: permission denied"
            case Unsupported: return "process: operation not supported"
            case Closed: return "process: resource is closed"
            case Failed(message): return message.clone()

impl Error for CommandError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `command: <reason>`, such as `command: operation timed out`.
    def message() -> String:
        match self:
            case InvalidInput: return "command: invalid input"
            case Unavailable: return "command: service unavailable"
            case Timeout: return "command: operation timed out"
            case OutputLimit: return "command: output limit exceeded"
            case Failed(message): return message.clone()

# A child program, its arguments, input and limits, assembled step by step. Arguments are separate list items passed to the program as they are, never joined into one string and never parsed by a shell, so spaces, quotes, `;` and `$` in an argument are plain text.
# `Command("git").arg("log").arg(user_text)` cannot turn `user_text` into a second command; there is no entry point that takes a shell command line.
export type Command:
    # The program to start, searched on the PATH. It is not a command line: put each argument in `arguments`.
    program: String
    # Arguments after the program name, one list item each.
    arguments: List[String] = []
    # Bytes written to the program's standard input.
    input: Bytes = "".to_bytes()
    # Output bound across both streams; none means the runtime default.
    max_output_bytes: Optional[Int] = none
    # Time allowed before the program is killed; none waits without a bound.
    timeout: Optional[Duration] = none

impl Command:
    # Appends one argument, passed to the program unchanged.
    var def arg(value: String) -> Unit:
        self.arguments.append(value)

    # Appends each value as its own argument, in order.
    var def args(values: List[String]) -> Unit:
        for value in values:
            self.arguments.append(value.clone())

    # Runs the program directly, without a shell, and waits for it, as `Commands.run` does.
    def run() -> Result[CommandOutput, CommandError]:
        return commands().run(
            self.program.clone(), self.arguments.clone(), self.input.clone(),
            self.max_output_bytes, self.timeout
        )

# Returns child-process operations for the current host.
export def commands() -> Commands:
    return msstd_process_commands()

# Returns the host-supplied startup arguments, excluding the executable path.
# Each call returns an owned list; mutations do not change later calls or native argv.
export def arguments() -> List[String]:
    return msrt_args()

# Returns controls and process information for the current process.
export def control() -> ProcessControl:
    return msstd_process_control()

# Canonical standard-library declarations. Implementations are native.
# Read-only host details and selected controls for the current operating system.
export interface System:
    # Returns the operating system name, processor architecture, and logical CPU count for this host.
    def info() -> SystemInfo
    # Reads the live native directory; an OS query failure faults because this API has no Result.
    # A host service constructed with an explicit directory retains that base.
    def working_directory() -> String
    # Returns the host's name as reported by the operating system.
    # A name that is not valid UTF-8 returns Unsupported.
    def hostname() -> Result[String, SystemError]
    # Returns the current user's home directory path, from the host's environment or account database.
    # A path that is not valid UTF-8 returns Unsupported.
    def home_directory() -> Result[String, SystemError]
    # Returns the current user's name, numeric ids, home directory, and login shell.
    # The shell is empty when the host does not record one, and text that is not valid UTF-8 returns Unsupported.
    def user_info() -> Result[UserInfo, SystemError]
    # Returns one NetworkInterface for every address on every interface, including loopback.
    # An interface name that is not valid UTF-8 returns Unsupported.
    def network_interfaces() -> Result[List[NetworkInterface], SystemError]
    # Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
    def cpus() -> Result[List[CpuInfo], SystemError]
    # Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
    # A host query failure returns the matching SystemError.
    def metrics() -> Result[SystemMetrics, SystemError]
    # Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    def os_release() -> Result[String, SystemError]
    # Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    def os_version() -> Result[String, SystemError]
    # Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use the target's architecture name.
    def machine() -> Result[String, SystemError]
    # Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
    # A pid outside 0 through 2147483647 returns InvalidInput, and platforms without priorities return Unsupported.
    def get_priority(pid: Int) -> Result[Int, SystemError]
    # Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
    # Unix uses nice values; Windows maps ranges to native priority classes.
    def set_priority(pid: Int, priority: Int) -> Result[Unit, SystemError]

# Operating system and processor architecture for the current host.
export type SystemInfo:
    # Operating system identifier, such as linux, darwin, or windows; an open host identifier set.
    os: String
    # The processor architecture in common naming, such as `amd64`, `arm64`, or `386`.
    architecture: String
    # Number of logical CPUs the operating system reports as present for this process.
    cpu_count: Int

# User name, numeric identity, home directory, and login shell.
export type UserInfo:
    # Login name of the current user.
    username: String
    # Numeric user id of the current user; -1 on Windows, where ids are not numeric.
    uid: Int
    # Numeric primary group id of the current user; -1 on Windows, where ids are not numeric.
    gid: Int
    # Absolute path of the user's home directory from the account database.
    home: String
    # Path of the user's login shell, or an empty string when the host records none.
    shell: String

# Address and link metadata for one host network interface.
export type NetworkInterface:
    # Host name of the interface, such as `eth0` or `lo0`. Interfaces with several addresses appear once per address.
    name: String
    # The interface's IP address in textual form, such as `192.168.1.5` or `fe80::1`.
    address: String
    # The address's network mask in the same textual form as `address`, such as `255.255.255.0`.
    netmask: String
    # The IPv4/IPv6 alternative for the native address record.
    family: IpFamily
    # Hardware address as colon-separated lowercase hexadecimal, or an empty string for interfaces without one such as loopback.
    mac: String
    # True for a loopback interface, which only reaches the local host.
    internal: Bool
    # The operating system's numeric index for the interface, as used to select an interface for link-local IPv6 addresses.
    scope_id: Int

# Model, integer MHz speed (fractional MHz truncated), and cumulative integer millisecond
# counters for one logical CPU. irq includes hardware and software interrupt time.
export type CpuInfo:
    # Marketing name of the processor, such as `Intel(R) Core(TM) i7`; it can be empty where the host does not report one.
    model: String
    # Integer megahertz, not a time interval.
    speed_mhz: Int
    # The user, nice, system, idle, and irq fields are cumulative milliseconds.
    user: Int
    # Cumulative milliseconds this logical CPU spent running low-priority (niced) user processes.
    nice: Int
    # Cumulative milliseconds this logical CPU spent running kernel code.
    system: Int
    # Cumulative milliseconds this logical CPU spent idle.
    idle: Int
    # Cumulative milliseconds this logical CPU spent servicing hardware and software interrupts.
    irq: Int

# Host measurements: memory fields are bytes; load_average is 1/5/15-minute load
# (three zeros on Windows); available_parallelism is a usable logical-processor count.
export type SystemMetrics:
    # Installed physical memory in bytes.
    total_memory: Int
    # Physical memory in bytes that is completely unused; caches count as used, so it is usually smaller than `available_memory`.
    free_memory: Int
    # Estimated physical memory in bytes that new work can use without swapping, including reclaimable caches.
    available_memory: Int
    # Host boot uptime as a Duration with whole-second native resolution; not process uptime.
    uptime: Duration
    # Three Floats for the 1, 5, and 15 minute system load averages; all 0.0 on Windows.
    load_average: List[Float]
    # Logical processors this process may run on, which can be fewer than `SystemInfo.cpu_count` under CPU affinity limits.
    available_parallelism: Int

# Returns exactly `LE` or `BE` for the host's native byte order.
export def endianness() -> String:
    return msstd_system_endianness()

# Returns the host's line-ending sequence.
export def end_of_line() -> String:
    return msstd_system_end_of_line()

# Returns the conventional null-device path for the host.
export def dev_null() -> String:
    return msstd_system_dev_null()

# Returns Linux, Darwin, or Windows_NT on the supported hosts; other hosts use their operating system name.
export def os_type() -> String:
    return msstd_system_os_type()

# Returns native signal/error/loader/priority constants by name.
# Names and values vary by host; missing entries do not imply a portable numeric default.
export def constants() -> Map[String, Int]:
    return msstd_system_constants()

# Errors returned when a requested host operation is unavailable or denied.
export type SystemError:
    # A pid is outside 0 through 2147483647, a priority is outside -20 through 19, or the host rejected an argument.
    case InvalidInput
    # Host data could not be interpreted; reserved for malformed host answers.
    case InvalidData
    # Reserved for results beyond a configured bound; the current operations do not return it.
    case LimitExceeded
    # The host reported that the target does not exist.
    case NotFound
    # The host reported that the target already exists.
    case AlreadyExists
    # The host refused the operation for lack of privilege, such as raising another process's priority.
    case PermissionDenied
    # The host or platform cannot provide the value, or the value is not valid UTF-8 and cannot become a String.
    case Unsupported
    # Reserved for operations on a closed system handle; the current operations do not return it.
    case Closed
    # The host reported another failure while querying or changing system state.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name paths.
        message: String
    )

impl Error for SystemError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `system: <reason>`.
    def message() -> String:
        match self:
            case InvalidInput: return "system: invalid input"
            case InvalidData: return "system: invalid data"
            case LimitExceeded: return "system: limit exceeded"
            case NotFound: return "system: not found"
            case AlreadyExists: return "system: already exists"
            case PermissionDenied: return "system: permission denied"
            case Unsupported: return "system: operation not supported"
            case Closed: return "system: resource is closed"
            case Failed(message): return message.clone()

# Returns system information and controls for the current host.
export def system() -> System:
    return msstd_process_system()
