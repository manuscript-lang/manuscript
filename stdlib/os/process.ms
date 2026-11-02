import Closeable from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import IpFamily from "@std/net/net.ms"
import ReadStream from "@std/io/io.ms"
import WriteStream from "@std/io/io.ms"
import (
    msrt_args,
    msstd_system_endianness,
    msstd_system_end_of_line,
    msstd_system_dev_null,
    msstd_system_os_type,
    msstd_system_constants,
    msstd_process_commands,
    msstd_process_control,
    msstd_process_system,
    msstd_process_subprocess_stdin,
    msstd_process_subprocess_stream,
    msstd_process_subprocess_wait,
    msstd_process_subprocess_max_resident,
    msstd_process_subprocess_terminate,
    msstd_process_subprocess_kill,
    msstd_process_subprocess_close
) from "@std/internal/process.ms"

# Captured exit status and standard output/error from a completed command.
export type CommandOutput:
    # The child's exit status; 0 conventionally means success. A nonzero status is still an Ok result, and a child ended by a signal reports -1 on Unix.
    exit_code: Int
    # Everything the child wrote to standard output, as raw bytes that may not be valid UTF-8.
    stdout: Bytes
    # Everything the child wrote to standard error, as raw bytes that may not be valid UTF-8.
    stderr: Bytes
    # The child's peak resident set size in bytes, or 0 when the host cannot report it.
    max_resident_bytes: Int

# Where a child's standard input, output, or error goes, chosen per stream.
# `spawn("make", [], stdout: Stdio.Inherit, stderr: Stdio.Inherit)` lets the child's output reach the parent's terminal while stdin stays piped.
export type Stdio:
    # An OS pipe to the parent, read or written through the Subprocess's stream.
    case Pipe
    # The parent's own stream, so the child reads or writes it directly.
    case Inherit
    # The null device: input is at end of file, output is discarded.
    case Null

# The shape of `run` and `spawn`, for code that takes child-process operations as a parameter so a test can pass a fake. Programs call the module functions `run` and `spawn` directly.
export interface Commands:
    # Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
    # Output beyond `max_output_bytes` in total across both streams returns OutputLimit, `timeout` returns Timeout, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
    # `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns InvalidInput. A `cwd` that does not exist returns Unavailable. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = "".to_bytes(),
        max_output_bytes: Int?,
        timeout: Duration?,
        cwd: String?,
        env: Map[String, String] = Map[String, String]()
    ) CommandOutput!
    # Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess that its scope closes. `arguments` follow the program name; `stdin`, `stdout`, and `stderr` each choose a pipe (the default), the parent's own stream, or the null device. Returns InvalidInput, Unavailable, or Failed when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
    # `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns InvalidInput. A `cwd` that does not exist returns Unavailable. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio = Stdio.Pipe,
        stdout: Stdio = Stdio.Pipe,
        stderr: Stdio = Stdio.Pipe,
        cwd: String?,
        env: Map[String, String] = Map[String, String]()
    ) Subprocess!

# The runtime handle behind a `Subprocess`.
export extern type NativeSubprocess

# A long-lived child process with live stdin, stdout, and stderr streams. Closing it
# kills the child's process group, joins it, and closes all three streams.
# A stream spawned as Stdio.Inherit or Stdio.Null has no pipe: it is already closed, so reads and writes return Closed.
export type Subprocess:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeSubprocess

impl Closeable for Subprocess:
    # Kills the process group, joins the child, kills leftover group members, and closes all three streams. Idempotent; scope exit calls it.
    var fn close() Unit!:
        msstd_process_subprocess_close(self.native)
        return ok(unit)

impl Subprocess:
    # The child's standard input as a WriteStream; writes block when the pipe is full. Closing the stream delivers end-of-input to the child.
    fn stdin() WriteStream:
        return msstd_process_subprocess_stdin(self.native)

    # The child's standard output as a ReadStream over the OS pipe; reads block until output or end-of-file, and nothing is buffered without bound.
    fn stdout() ReadStream:
        return msstd_process_subprocess_stream(self.native, 1)

    # The child's standard error as a ReadStream over the OS pipe, with the same blocking and backpressure behavior as stdout.
    fn stderr() ReadStream:
        return msstd_process_subprocess_stream(self.native, 2)

    # Waits for the child to exit and returns its exit status. Returns Timeout if `timeout` elapses first, leaving the child running.
    fn wait(timeout: Duration?) Int!:
        return msstd_process_subprocess_wait(self.native, timeout)

    # The child's peak resident set size in bytes, known once `wait` has returned its exit status; 0 before that or when the host cannot report it.
    fn max_resident_bytes() Int:
        return msstd_process_subprocess_max_resident(self.native)

    # Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it kills the direct process. Does not wait.
    fn terminate() Unit:
        return msstd_process_subprocess_terminate(self.native)

    # Sends SIGKILL to the child's process group. Does not wait.
    fn kill() Unit:
        return msstd_process_subprocess_kill(self.native)

# Process and operating-system controls for the current process.
# `watch_signals` observes signals without claiming them; SIGINT/SIGTERM still cancel the native application.
# `next()` and code following it have no shutdown guarantee. Register `Closeable` cleanup
# and finish shutdown work directly in the shielded close call after joining cancelled workers.
interface ProcessControl:
    # Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
    # This is not Unix time or a Clock Instant; prefer monotonic().difference(start) for timing.
    fn monotonic_time() Int
    # Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
    # Capacity must be 1..1048576; omission/none uses 128 buffered signals.
    # Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
    # Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
    fn watch_signals(signals: List[Int], capacity: Int?) SignalStream!
    # Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
    fn constrained_memory() Int!
    # Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
    fn available_memory() Int!
    # Returns the current process title.
    # Platforms that cannot read it return Unsupported.
    fn title() String!
    # Sets the process title shown by tools such as `ps`.
    # A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.
    fn set_title(title: String) Unit!
    # Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
    # A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.
    fn initialize_groups(username: String, gid: Int) Unit!
    # Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
    # `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.
    fn replace(
        program: String,
        arguments: List[String],
        environment: Map[String, String]
    ) Unit!
    # Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
    # Text that is not valid UTF-8 returns Unsupported.
    fn info() ProcessInfo!
    # Returns heap and resident memory statistics for this process, in bytes.
    fn memory_usage() MemoryUsage!
    # Returns cumulative user and kernel CPU time consumed by this process in microseconds.
    # Platforms without resource accounting return Unsupported.
    fn cpu_usage() CpuUsage!
    # Returns elapsed Duration since runtime initialization, rather than host boot.
    fn uptime() Duration!
    # Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
    fn environment() Map[String, String]!
    # Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
    # An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.
    fn set_environment(name: String, value: String?) Unit!
    # Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
    # Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.
    fn load_environment(path: String, max_bytes: Int?) Unit!
    # Reads the live process directory, preserving OS failures as `Error` values.
    fn working_directory() String!
    # Changes the working directory of the whole process, affecting relative paths everywhere.
    # A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.
    fn change_directory(path: String) Unit!
    # Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
    # Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination. A pid that names no process returns NotFound.
    fn send_signal(pid: Int, signal: Int) Unit!
    # Returns the numeric ids of the supplementary groups of the process.
    # Windows returns Unsupported.
    fn groups() List[Int]!
    # Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
    # Platforms without them return Unsupported.
    fn resource_usage() ResourceUsage!
    # Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
    fn umask(mask: Int) Int!
    # Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
    # Identity changes require OS permission and are Unsupported on Windows.
    fn set_identity(kind: String, id: Int) Unit!
    # Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
    # Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.
    fn set_groups(groups: List[Int]) Unit!

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
# `next()` and following code have no shutdown guarantee; use registered `Closeable` cleanup.
export interface SignalStream:
    # Stops observing signals, wakes a pending `next` with Closed, and waits for it.
    # Safe to call repeatedly.
    fn close() Unit
    # Waits for the next observed signal and returns its number. Signals arriving while no call waits are buffered up to the stream's capacity.
    # Returns Closed after `close`. Cancelling the waiting task unwinds it.
    fn next() Int!

# The child-process operations of the current host.
fn host_commands() Commands:
    return msstd_process_commands()

# Returns the host-supplied startup arguments, excluding the executable path.
# Each call returns an owned list; mutations do not change later calls or native argv.
export fn arguments() List[String]:
    return msrt_args()

# The controls and process information of the current process.
fn host_control() ProcessControl:
    return msstd_process_control()

# Canonical standard-library declarations. Implementations are native.
# Read-only host details and selected controls for the current operating system.
interface System:
    # Returns the operating system name, processor architecture, and logical CPU count for this host.
    fn info() SystemInfo
    # Reads the live native directory; an OS query failure faults because this API has no Result.
    # A host service constructed with an explicit directory retains that base.
    fn working_directory() String
    # Returns the host's name as reported by the operating system.
    # A name that is not valid UTF-8 returns Unsupported.
    fn hostname() String!
    # Returns the current user's home directory path, from the host's environment or account database.
    # A path that is not valid UTF-8 returns Unsupported.
    fn home_directory() String!
    # Returns the current user's name, numeric ids, home directory, and login shell.
    # The shell is empty when the host does not record one, and text that is not valid UTF-8 returns Unsupported.
    fn user_info() UserInfo!
    # Returns one NetworkInterface for every address on every interface, including loopback.
    # An interface name that is not valid UTF-8 returns Unsupported.
    fn network_interfaces() List[NetworkInterface]!
    # Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
    fn cpus() List[CpuInfo]!
    # Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
    # A host query failure returns an `Error` describing it.
    fn metrics() SystemMetrics!
    # Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    fn os_release() String!
    # Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    fn os_version() String!
    # Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use the target's architecture name.
    fn machine() String!
    # Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
    # A pid outside 0 through 2147483647 returns InvalidInput, and platforms without priorities return Unsupported.
    fn get_priority(pid: Int) Int!
    # Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
    # Unix uses nice values; Windows maps ranges to native priority classes.
    fn set_priority(pid: Int, priority: Int) Unit!

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
export fn endianness() String:
    return msstd_system_endianness()

# Returns the host's line-ending sequence.
export fn end_of_line() String:
    return msstd_system_end_of_line()

# Returns the conventional null-device path for the host.
export fn dev_null() String:
    return msstd_system_dev_null()

# Returns Linux, Darwin, or Windows_NT on the supported hosts; other hosts use their operating system name.
export fn os_type() String:
    return msstd_system_os_type()

# Returns native signal/error/loader/priority constants by name.
# Names and values vary by host; missing entries do not imply a portable numeric default.
export fn constants() Map[String, Int]:
    return msstd_system_constants()

# The system information and controls of the current host.
fn host_system() System:
    return msstd_process_system()

# Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
# Output beyond `max_output_bytes` in total across both streams returns OutputLimit, `timeout` returns Timeout, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
# `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns InvalidInput. A `cwd` that does not exist returns Unavailable. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
export fn run(
    program: String,
    arguments: List[String],
    input: Bytes = "".to_bytes(),
    max_output_bytes: Int?,
    timeout: Duration?,
    cwd: String?,
    env: Map[String, String] = Map[String, String]()
) CommandOutput!:
    return host_commands().run(
        program, arguments, input, max_output_bytes, timeout, cwd, env
    )

# Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess that its scope closes. `arguments` follow the program name; `stdin`, `stdout`, and `stderr` each choose a pipe (the default), the parent's own stream, or the null device. Returns InvalidInput, Unavailable, or Failed when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
# `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns InvalidInput. A `cwd` that does not exist returns Unavailable. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
export fn spawn(
    program: String,
    arguments: List[String],
    stdin: Stdio = Stdio.Pipe,
    stdout: Stdio = Stdio.Pipe,
    stderr: Stdio = Stdio.Pipe,
    cwd: String?,
    env: Map[String, String] = Map[String, String]()
) Subprocess!:
    return host_commands().spawn(program, arguments, stdin, stdout, stderr, cwd, env)

# Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
# This is not Unix time or a Clock Instant; prefer monotonic().difference(start) for timing.
export fn monotonic_time() Int:
    return host_control().monotonic_time()

# Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
# Capacity must be 1..1048576; omission/none uses 128 buffered signals.
# Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
# Code after next() has no shutdown guarantee; use registered with/Closeable cleanup.
export fn watch_signals(signals: List[Int], capacity: Int?) SignalStream!:
    return host_control().watch_signals(signals, capacity)

# Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
export fn constrained_memory() Int!:
    return host_control().constrained_memory()

# Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
export fn available_memory() Int!:
    return host_control().available_memory()

# Returns the current process title.
# Platforms that cannot read it return Unsupported.
export fn title() String!:
    return host_control().title()

# Sets the process title shown by tools such as `ps`.
# A title with NUL or newline returns InvalidInput, and platforms that cannot rename a process return Unsupported.
export fn set_title(title: String) Unit!:
    return host_control().set_title(title)

# Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
# A failed user lookup returns Failed, a `gid` outside 0 through 2147483647 returns InvalidInput, and a lack of privilege returns PermissionDenied.
export fn initialize_groups(username: String, gid: Int) Unit!:
    return host_control().initialize_groups(username, gid)

# Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
# `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return InvalidInput, and exec failures return NotFound, PermissionDenied, or Failed. Unsupported on Windows.
export fn replace(
    program: String,
    arguments: List[String],
    environment: Map[String, String]
) Unit!:
    return host_control().replace(program, arguments, environment)

# Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
# Text that is not valid UTF-8 returns Unsupported.
export fn process_info() ProcessInfo!:
    return host_control().info()

# Returns heap and resident memory statistics for this process, in bytes.
export fn memory_usage() MemoryUsage!:
    return host_control().memory_usage()

# Returns cumulative user and kernel CPU time consumed by this process in microseconds.
# Platforms without resource accounting return Unsupported.
export fn cpu_usage() CpuUsage!:
    return host_control().cpu_usage()

# Returns elapsed Duration since runtime initialization, rather than host boot.
export fn uptime() Duration!:
    return host_control().uptime()

# Reads a fresh live process environment map; non-UTF-8 entries return Unsupported.
export fn environment() Map[String, String]!:
    return host_control().environment()

# Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
# An empty name, or a name or value with `=` or NUL, returns InvalidInput. The change is visible to child processes started afterwards.
export fn set_environment(name: String, value: String?) Unit!:
    return host_control().set_environment(name, value)

# Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
# Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns InvalidData and changes nothing. A file larger than `max_bytes` returns LimitExceeded.
export fn load_environment(path: String, max_bytes: Int?) Unit!:
    return host_control().load_environment(path, max_bytes)

# Reads the live process directory, preserving OS failures as `Error` values.
export fn working_directory() String!:
    return host_control().working_directory()

# Changes the working directory of the whole process, affecting relative paths everywhere.
# A missing path returns NotFound, a path containing NUL returns InvalidInput, and a denied path returns PermissionDenied.
export fn change_directory(path: String) Unit!:
    return host_control().change_directory(path)

# Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
# Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination. A pid that names no process returns NotFound.
export fn send_signal(pid: Int, signal: Int) Unit!:
    return host_control().send_signal(pid, signal)

# Returns the numeric ids of the supplementary groups of the process.
# Windows returns Unsupported.
export fn groups() List[Int]!:
    return host_control().groups()

# Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
# Platforms without them return Unsupported.
export fn resource_usage() ResourceUsage!:
    return host_control().resource_usage()

# Sets mask 0..511 (0777) and returns the previous mask; Unsupported on Windows.
export fn umask(mask: Int) Int!:
    return host_control().umask(mask)

# Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return InvalidInput.
# Identity changes require OS permission and are Unsupported on Windows.
export fn set_identity(kind: String, id: Int) Unit!:
    return host_control().set_identity(kind, id)

# Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
# Invalid ids return InvalidInput, a lack of privilege returns PermissionDenied, and Windows returns Unsupported.
export fn set_groups(groups: List[Int]) Unit!:
    return host_control().set_groups(groups)

# Returns the operating system name, processor architecture, and logical CPU count for this host.
export fn system_info() SystemInfo:
    return host_system().info()

# Returns the host's name as reported by the operating system.
# A name that is not valid UTF-8 returns Unsupported.
export fn hostname() String!:
    return host_system().hostname()

# Returns the current user's home directory path, from the host's environment or account database.
# A path that is not valid UTF-8 returns Unsupported.
export fn home_directory() String!:
    return host_system().home_directory()

# Returns the current user's name, numeric ids, home directory, and login shell.
# The shell is empty when the host does not record one, and text that is not valid UTF-8 returns Unsupported.
export fn user_info() UserInfo!:
    return host_system().user_info()

# Returns one NetworkInterface for every address on every interface, including loopback.
# An interface name that is not valid UTF-8 returns Unsupported.
export fn network_interfaces() List[NetworkInterface]!:
    return host_system().network_interfaces()

# Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
export fn cpus() List[CpuInfo]!:
    return host_system().cpus()

# Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
# A host query failure returns an `Error` describing it.
export fn metrics() SystemMetrics!:
    return host_system().metrics()

# Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
# Returns Unsupported where the host does not expose it.
export fn os_release() String!:
    return host_system().os_release()

# Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
# Returns Unsupported where the host does not expose it.
export fn os_version() String!:
    return host_system().os_version()

# Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use the target's architecture name.
export fn machine() String!:
    return host_system().machine()

# Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
# A pid outside 0 through 2147483647 returns InvalidInput, and platforms without priorities return Unsupported.
export fn get_priority(pid: Int) Int!:
    return host_system().get_priority(pid)

# Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
# Unix uses nice values; Windows maps ranges to native priority classes.
export fn set_priority(pid: Int, priority: Int) Unit!:
    return host_system().set_priority(pid, priority)
