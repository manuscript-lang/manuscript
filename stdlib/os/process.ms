import Closeable from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import Promise, owned_promise from "@std/concurrency/promise.ms"
import access, join, stat from "@std/os/fs.ms"
import IpFamily from "@std/net/net.ms"
import (
    ReadStream,
    WriteStream,
    Source,
    stream,
    descriptor_reader,
    descriptor_writer
) from "@std/io/io.ms"
import (
    msrt_args,
    msstd_system_endianness,
    msstd_system_end_of_line,
    msstd_system_dev_null,
    msstd_system_os_type,
    msstd_system_constants,
    msstd_process_command_run,
    msstd_process_command_spawn,
    msstd_process_subprocess_stream_id,
    msstd_process_subprocess_wait,
    msstd_process_subprocess_max_resident,
    msstd_process_subprocess_terminate,
    msstd_process_subprocess_kill,
    msstd_process_subprocess_close,
    msstd_process_available_memory,
    msstd_process_change_directory,
    msstd_process_constrained_memory,
    msstd_process_cpu_usage,
    msstd_process_environment_map,
    msstd_process_groups,
    msstd_process_initialize_groups,
    msstd_process_load_environment,
    msstd_process_memory_usage,
    msstd_process_monotonic_time,
    msstd_process_resource_usage,
    msstd_process_send_signal,
    msstd_process_set_environment,
    msstd_process_set_groups,
    msstd_process_set_identity,
    msstd_process_set_title,
    msstd_process_title,
    msstd_process_umask,
    msstd_process_elapsed,
    msstd_process_watch_signals,
    msstd_process_signal_next,
    msstd_process_signal_close,
    msstd_process_working_directory,
    msstd_system_get_priority,
    msstd_system_home_directory,
    msstd_system_hostname,
    msstd_system_machine,
    msstd_system_os_release,
    msstd_system_os_version,
    msstd_system_set_priority,
    msstd_system_working_directory,
    msstd_process_replace,
    msstd_process_info_pid,
    msstd_process_info_parent_pid,
    msstd_process_info_executable,
    msstd_process_info_arguments,
    msstd_process_info_os,
    msstd_process_info_architecture,
    msstd_process_info_uid,
    msstd_process_info_gid,
    msstd_process_info_effective_uid,
    msstd_process_info_effective_gid,
    msstd_system_info_os,
    msstd_system_info_architecture,
    msstd_system_info_cpu_count,
    msstd_system_user_info_status,
    msstd_system_user_info_username,
    msstd_system_user_info_uid,
    msstd_system_user_info_gid,
    msstd_system_user_info_home,
    msstd_system_user_info_shell,
    msstd_system_network_interfaces_status,
    msstd_system_network_interfaces_count,
    msstd_system_network_interfaces_name,
    msstd_system_network_interfaces_address,
    msstd_system_network_interfaces_netmask,
    msstd_system_network_interfaces_family,
    msstd_system_network_interfaces_mac,
    msstd_system_network_interfaces_internal,
    msstd_system_network_interfaces_scope_id,
    msstd_system_cpus_status,
    msstd_system_cpus_count,
    msstd_system_cpus_model,
    msstd_system_cpus_speed_mhz,
    msstd_system_cpus_user,
    msstd_system_cpus_nice,
    msstd_system_cpus_system,
    msstd_system_cpus_idle,
    msstd_system_cpus_irq,
    msstd_system_metrics_status,
    msstd_system_metrics_total_memory,
    msstd_system_metrics_free_memory,
    msstd_system_metrics_available_memory,
    msstd_system_metrics_uptime,
    msstd_system_metrics_load_average,
    msstd_system_metrics_available_parallelism
) from "@std/internal/process.ms"

// Captured exit status and standard output/error from a completed command.
export type CommandOutput:
    // The child's exit status; 0 conventionally means success. A nonzero status is still an Ok result, and a child ended by a signal reports -1 on Unix.
    exit_code: Int
    // Everything the child wrote to standard output, as raw bytes that may not be valid UTF-8.
    stdout: Bytes
    // Everything the child wrote to standard error, as raw bytes that may not be valid UTF-8.
    stderr: Bytes
    // The child's peak resident set size in bytes, or 0 when the host cannot report it.
    max_resident_bytes: Int

// Where a child's standard input, output, or error goes, chosen per stream.
// `spawn("make", [], stdout: Stdio.Inherit, stderr: Stdio.Inherit)` lets the child's output reach the parent's terminal while stdin stays piped.
export type Stdio:
    // An OS pipe to the parent, read or written through the Subprocess's stream.
    case Pipe
    case Inherit  // The parent's own stream, so the child reads or writes it directly.
    case Null  // The null device: input is at end of file, output is discarded.

// The shape of `run` and `spawn`, for code that takes child-process operations as a parameter so a test can pass a fake. Programs call the module functions `run` and `spawn` directly.
export interface Commands:
    /*
    Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
    Output beyond `max_output_bytes` in total across both streams returns EOVERFLOW, `timeout` returns ETIMEDOUT, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
    `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns EAGAIN. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
    */
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = "".to_bytes(),
        max_output_bytes: Int?,
        timeout: Duration?,
        cwd: String?,
        env: Map[String, String] = Map[String, String]()
    ) CommandOutput!
    // Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess that its scope closes. `arguments` follow the program name; `stdin`, `stdout`, and `stderr` each choose a pipe (the default), the parent's own stream, or the null device. Returns EINVAL, EAGAIN, or EIO when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
    // `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns EAGAIN. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio = Stdio.Pipe,
        stdout: Stdio = Stdio.Pipe,
        stderr: Stdio = Stdio.Pipe,
        cwd: String?,
        env: Map[String, String] = Map[String, String]()
    ) Subprocess!

// The runtime handle behind a `Subprocess`.
export extern type NativeSubprocess

/*
A long-lived child process with live stdin, stdout, and stderr streams. Closing it
kills the child's process group, joins it, and closes all three streams.
A stream spawned as Stdio.Inherit or Stdio.Null has no pipe: it is already closed, so reads and writes return EBADF.
*/
export type Subprocess:
    // The runtime handle; it is released by `close` and owned by this value.
    native: NativeSubprocess

impl Closeable for Subprocess:
    // Kills the process group, joins the child, kills leftover group members, and closes all three streams. Idempotent; scope exit calls it.
    var fn close() Unit!:
        msstd_process_subprocess_close(self.native)
        return ok(unit)

impl Subprocess:
    // The child's standard input as a WriteStream; writes block when the pipe is full. Closing the stream delivers end-of-input to the child.
    fn stdin() WriteStream[Bytes]:
        return descriptor_writer(msstd_process_subprocess_stream_id(self.native, 0))

    // The child's standard output as a ReadStream over the OS pipe; reads block until output or end-of-file, and nothing is buffered without bound.
    fn stdout() ReadStream[Bytes]:
        return descriptor_reader(msstd_process_subprocess_stream_id(self.native, 1))

    // The child's standard error as a ReadStream over the OS pipe, with the same blocking and backpressure behavior as stdout.
    fn stderr() ReadStream[Bytes]:
        return descriptor_reader(msstd_process_subprocess_stream_id(self.native, 2))

    // Waits for the child to exit and returns its exit status. Returns ETIMEDOUT if `timeout` elapses first, leaving the child running.
    fn wait(timeout: Duration?) Int!:
        return msstd_process_subprocess_wait(self.native, timeout)

    // The child's peak resident set size in bytes, known once `wait` has returned its exit status; 0 before that or when the host cannot report it.
    fn max_resident_bytes() Int:
        return msstd_process_subprocess_max_resident(self.native)

    // Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it kills the direct process. Does not wait.
    fn terminate() Unit:
        return msstd_process_subprocess_terminate(self.native)

    // Sends SIGKILL to the child's process group. Does not wait.
    fn kill() Unit:
        return msstd_process_subprocess_kill(self.native)

// Identity and invocation details for the current process.
export type ProcessInfo:
    // Operating system id of this process.
    pid: Int
    // Operating system id of the parent process at the time of the call.
    parent_pid: Int
    // Absolute path of the running program file.
    executable: String
    // Live native argv including argv[0]; process.arguments() is the supplied startup tail without it.
    arguments: List[String]
    // Operating system name, such as `linux`, `darwin`, or `windows`.
    os: String
    // Processor architecture name, such as `amd64` or `arm64`.
    architecture: String
    // Real user id; -1 on Windows, where ids are not numeric.
    uid: Int
    // Real group id; -1 on Windows, where ids are not numeric.
    gid: Int
    // Effective user id used for permission checks; -1 on Windows.
    effective_uid: Int
    // Effective group id used for permission checks; -1 on Windows.
    effective_gid: Int

// Memory statistics for the current process; every field is bytes.
export type MemoryUsage:
    // Bytes of heap memory occupied by live objects and objects not yet collected.
    heap_used: Int
    // Bytes of heap spans currently in use, which is at least `heap_used`.
    heap_total: Int
    // Bytes of heap memory obtained from the operating system, including idle spans.
    heap_system: Int
    // Bytes the runtime obtained from the operating system outside the heap, such as stacks and internal tables.
    external: Int
    // Bytes of physical memory the operating system reports as resident for the process.
    resident: Int

// Cumulative CPU time consumed by the current process, in integer microseconds.
export type CpuUsage:
    // User CPU time in microseconds.
    user_microseconds: Int
    // Kernel CPU time in microseconds.
    system_microseconds: Int

/*
Kernel resource counters for the current process. CPU times are integer microseconds;
max_resident_bytes is bytes; other fields are counts, not durations or byte totals.
Filesystem reads/writes count native block I/O on Unix and I/O operations on Windows.
Unavailable Windows fault/context-switch counters are zero.
*/
export type ResourceUsage:
    // Cumulative CPU time spent running this process's own code, in microseconds.
    user_microseconds: Int
    // Cumulative CPU time the kernel spent on behalf of this process, in microseconds.
    system_microseconds: Int
    // Peak physical memory the process has held at once, in bytes.
    max_resident_bytes: Int
    // Page faults served without disk I/O, as a count.
    minor_faults: Int
    // Page faults that required disk I/O, as a count.
    major_faults: Int
    // Block input operations charged to the process, as a count.
    filesystem_reads: Int
    // Block output operations charged to the process, as a count.
    filesystem_writes: Int
    // Context switches where the process gave up the CPU, such as to wait for I/O, as a count.
    voluntary_switches: Int
    // Context switches where the scheduler preempted the process, as a count.
    involuntary_switches: Int

// The runtime observer behind `watch_signals`; signals arriving while no read waits are buffered.
export extern type NativeSignals

type SignalSource:
    signals: NativeSignals

impl Source[Int] for SignalSource:
    var fn next() Int?!:
        return ok(try msstd_process_signal_next(self.signals))

    // Stops observing signals and wakes a pending read with EBADF.
    var fn close() Unit!:
        msstd_process_signal_close(self.signals)
        return ok(unit)

// Returns the host-supplied startup arguments, excluding the executable path.
// Each call returns an owned list; mutations do not change later calls or native argv.
export fn arguments() List[String]:
    return msrt_args()

// Operating system and processor architecture for the current host.
export type SystemInfo:
    // Operating system identifier, such as linux, darwin, or windows; an open host identifier set.
    os: String
    // The processor architecture in common naming, such as `amd64`, `arm64`, or `386`.
    architecture: String
    // Number of logical CPUs the operating system reports as present for this process.
    cpu_count: Int

// User name, numeric identity, home directory, and login shell.
export type UserInfo:
    // Login name of the current user.
    username: String
    // Numeric user id of the current user; -1 on Windows, where ids are not numeric.
    uid: Int
    // Numeric primary group id of the current user; -1 on Windows, where ids are not numeric.
    gid: Int
    // Absolute path of the user's home directory from the account database.
    home: String
    // Path of the user's login shell, or an empty string when the host records none.
    shell: String

// Address and link metadata for one host network interface.
export type NetworkInterface:
    // Host name of the interface, such as `eth0` or `lo0`. Interfaces with several addresses appear once per address.
    name: String
    // The interface's IP address in textual form, such as `192.168.1.5` or `fe80::1`.
    address: String
    // The address's network mask in the same textual form as `address`, such as `255.255.255.0`.
    netmask: String
    // The IPv4/IPv6 alternative for the native address record.
    family: IpFamily
    // Hardware address as colon-separated lowercase hexadecimal, or an empty string for interfaces without one such as loopback.
    mac: String
    // True for a loopback interface, which only reaches the local host.
    internal: Bool
    // The operating system's numeric index for the interface, as used to select an interface for link-local IPv6 addresses.
    scope_id: Int

// Model, integer MHz speed (fractional MHz truncated), and cumulative integer millisecond
// counters for one logical CPU. irq includes hardware and software interrupt time.
export type CpuInfo:
    // Marketing name of the processor, such as `Intel(R) Core(TM) i7`; it can be empty where the host does not report one.
    model: String
    // Integer megahertz, not a time interval.
    speed_mhz: Int
    // The user, nice, system, idle, and irq fields are cumulative milliseconds.
    user: Int
    // Cumulative milliseconds this logical CPU spent running low-priority (niced) user processes.
    nice: Int
    // Cumulative milliseconds this logical CPU spent running kernel code.
    system: Int
    // Cumulative milliseconds this logical CPU spent idle.
    idle: Int
    // Cumulative milliseconds this logical CPU spent servicing hardware and software interrupts.
    irq: Int

// Host measurements: memory fields are bytes; load_average is 1/5/15-minute load
// (three zeros on Windows); available_parallelism is a usable logical-processor count.
export type SystemMetrics:
    // Installed physical memory in bytes.
    total_memory: Int
    // Physical memory in bytes that is completely unused; caches count as used, so it is usually smaller than `available_memory`.
    free_memory: Int
    // Estimated physical memory in bytes that new work can use without swapping, including reclaimable caches.
    available_memory: Int
    // Host boot uptime as a Duration with whole-second native resolution; not process uptime.
    uptime: Duration
    // Three Floats for the 1, 5, and 15 minute system load averages; all 0.0 on Windows.
    load_average: List[Float]
    // Logical processors this process may run on, which can be fewer than `SystemInfo.cpu_count` under CPU affinity limits.
    available_parallelism: Int

// Returns exactly `LE` or `BE` for the host's native byte order.
export fn endianness() String:
    return msstd_system_endianness()

// Returns the host's line-ending sequence.
export fn end_of_line() String:
    return msstd_system_end_of_line()

// Returns the conventional null-device path for the host.
export fn dev_null() String:
    return msstd_system_dev_null()

// Returns Linux, Darwin, or Windows_NT on the supported hosts; other hosts use their operating system name.
export fn os_type() String:
    return msstd_system_os_type()

// Returns native signal/error/loader/priority constants by name.
// Names and values vary by host; missing entries do not imply a portable numeric default.
export fn constants() Map[String, Int]:
    return msstd_system_constants()

// The names of an environment map, in the order of its values.
fn environment_names(environment: Map[String, String]) List[String]:
    var names: List[String] = []
    for entry in environment.entries():
        names.append(entry.key.clone())
    return names

// The values of an environment map, in the order of its names.
fn environment_values(environment: Map[String, String]) List[String]:
    var values: List[String] = []
    for entry in environment.entries():
        values.append(entry.value.clone())
    return values

type RunArgs:
    program: String
    arguments: List[String]
    input: Bytes
    max_output_bytes: Int?
    timeout: Duration?
    cwd: String?
    env: Map[String, String]

/*
Starts `program` directly, without a shell, searching the PATH, and returns a promise that finishes when it does. `arguments` are passed after the program name, `input` is written to its standard input, and its output is captured.
Output beyond `max_output_bytes` in total across both streams returns EOVERFLOW, `timeout` returns ETIMEDOUT, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
`cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns EAGAIN. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
*/
export fn run(
    program: String,
    arguments: List[String],
    input: Bytes = "".to_bytes(),
    max_output_bytes: Int?,
    timeout: Duration?,
    cwd: String?,
    env: Map[String, String] = Map[String, String]()
) Promise[CommandOutput]:
    return owned_promise[RunArgs, CommandOutput](
        RunArgs(
            program: program.clone(), arguments: arguments.clone(),
            input: input.clone(), max_output_bytes: max_output_bytes, timeout: timeout,
            cwd: cwd.clone(), env: env.clone()
        ),
        fn a: msstd_process_command_run(
            a.program, a.arguments, a.input, a.max_output_bytes, a.timeout, a.cwd,
            environment_names(a.env), environment_values(a.env)
        )
    )

// Starts `program` directly, without a shell, searching the PATH, and returns a live Subprocess that its scope closes. `arguments` follow the program name; `stdin`, `stdout`, and `stderr` each choose a pipe (the default), the parent's own stream, or the null device. Returns EINVAL, EAGAIN, or EIO when it cannot start. Closing the Subprocess, or cancelling the acquiring execution, kills the child's process group.
// `cwd` is the child's working directory (none inherits the caller's); `env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns EAGAIN. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
export fn spawn(
    program: String,
    arguments: List[String],
    stdin: Stdio = Stdio.Pipe,
    stdout: Stdio = Stdio.Pipe,
    stderr: Stdio = Stdio.Pipe,
    cwd: String?,
    env: Map[String, String] = Map[String, String]()
) Subprocess!:
    return msstd_process_command_spawn(
        program, arguments, stdin, stdout, stderr, cwd, environment_names(env),
        environment_values(env)
    )

// Elapsed nanoseconds since native runtime initialization, sharing the uptime() origin.
// This is not Unix time or a Clock Instant; prefer monotonic().difference(start) for timing.
export fn monotonic_time() Int:
    return msstd_process_monotonic_time()

/*
Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
Capacity must be 1..1048576; omission/none uses 128 buffered signals.
Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
Each read yields the next signal number; the stream never ends on its own. Dropping it unregisters the observer.
Code after a read has no shutdown guarantee; use registered with/Closeable cleanup.
*/
export fn watch_signals(signals: List[Int], capacity: Int?) ReadStream[Int]!:
    let native = try msstd_process_watch_signals(signals, capacity)
    return ok(stream[Int](SignalSource(native)))

// Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
export fn constrained_memory() Int!:
    return msstd_process_constrained_memory()

// Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
export fn available_memory() Int!:
    return msstd_process_available_memory()

// Returns the current process title.
// Platforms that cannot read it return ENOTSUP.
export fn title() String!:
    return msstd_process_title()

// Sets the process title shown by tools such as `ps`.
// A title with NUL or newline returns EINVAL, and platforms that cannot rename a process return ENOTSUP.
export fn set_title(title: String) Unit!:
    return msstd_process_set_title(title)

// Replaces the supplementary group list with the groups of `username` from the account database plus `gid` first. Requires privilege.
// A failed user lookup returns EIO, a `gid` outside 0 through 2147483647 returns EINVAL, and a lack of privilege returns EACCES.
export fn initialize_groups(username: String, gid: Int) Unit!:
    return msstd_process_initialize_groups(username, gid)

// Replaces the running process image with `program` using exactly the given `arguments` as argv, where `arguments[0]` is the program name, and exactly the given `environment`. On success it never returns.
// `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return EINVAL, and exec failures return ENOENT, EACCES, or EIO. ENOTSUP on Windows.
export fn replace(
    program: String,
    arguments: List[String],
    environment: Map[String, String]
) Unit!:
    var names: List[String] = []
    var values: List[String] = []

    for entry in environment.entries():
        names.append(entry.key.clone())
        values.append(entry.value.clone())

    return msstd_process_replace(program, arguments, names, values)

// Returns the process id, parent id, executable path, arguments, platform, and real and effective user and group ids.
// Text that is not valid UTF-8 returns ENOTSUP.
export fn process_info() ProcessInfo!:
    return ok(
        ProcessInfo(
            pid: msstd_process_info_pid(), parent_pid: msstd_process_info_parent_pid(),
            executable: msstd_process_info_executable(),
            arguments: msstd_process_info_arguments(), os: msstd_process_info_os(),
            architecture: msstd_process_info_architecture(),
            uid: msstd_process_info_uid(), gid: msstd_process_info_gid(),
            effective_uid: msstd_process_info_effective_uid(),
            effective_gid: msstd_process_info_effective_gid()
        )
    )

// Returns heap and resident memory statistics for this process, in bytes.
export fn memory_usage() MemoryUsage!:
    return msstd_process_memory_usage()

// Returns cumulative user and kernel CPU time consumed by this process in microseconds.
// Platforms without resource accounting return ENOTSUP.
export fn cpu_usage() CpuUsage!:
    return msstd_process_cpu_usage()

// Returns elapsed Duration since runtime initialization, rather than host boot.
export fn uptime() Duration!:
    return msstd_process_elapsed()

/*
Finds the executable that running `name` would start, or none.
A name containing a path separator is checked without searching PATH. Otherwise each directory of `PATH` is searched in order, skipping empty entries. Candidates are tried as given, then on Windows with each `PATHEXT` extension (`.COM;.EXE;.BAT;.CMD` when unset); environment variable names are case-insensitive there. The result is a regular file the process may execute (any regular file on Windows) and is not made absolute or canonical.
Example: `which("git")` is `/usr/bin/git`.
*/
export fn which(name: String) String?:
    if name == "": return none

    let windows = os_type() == "Windows_NT"
    let has_path = name.contains("/") or (windows and name.contains("\\"))
    var extensions = List[String]()
    var separator = ":"
    var directories = List[String]()

    if windows:
        separator = ";"
        extensions = [".COM", ".EXE", ".BAT", ".CMD"]

    let env = environment()

    if env.is_ok():
        for entry in env.get(Map[String, String]()).entries():
            let key = if windows: entry.key.upper() else: entry.key
            if key == "PATH": directories = entry.value.split(separator)
            if key == "PATHEXT" and windows: extensions = entry.value.split(";")

    if has_path:
        directories = [""]

    for directory in directories:
        if directory == "" and not has_path: continue

        let candidate = if directory == "": name.clone() else: join(
            [directory.clone(), name.clone()]
        )
        if runnable(candidate, windows): return candidate

        for extension in extensions:
            if extension == "": continue
            if runnable("{candidate}{extension}", windows): return "{candidate}{extension}"

    return none

fn runnable(path: String, windows: Bool) Bool:
    let info = stat(path, true)
    if info.is_error() or not info.get().regular: return false
    if windows: return true

    return access(path, 1).is_ok()

// Reads a fresh live process environment map; non-UTF-8 entries return ENOTSUP.
export fn environment() Map[String, String]!:
    return msstd_process_environment_map()

// Sets environment variable `name` for this process to `value`, or removes it when `value` is none.
// An empty name, or a name or value with `=` or NUL, returns EINVAL. The change is visible to child processes started afterwards.
export fn set_environment(name: String, value: String?) Unit!:
    return msstd_process_set_environment(name, value)

// Reads `KEY=value` lines from the file at `path` and sets each variable that is not already present in the environment. Existing variables keep their values.
// Blank lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted values spanning lines are accepted. The whole file is validated first, so a malformed or non-UTF-8 file returns EBADMSG and changes nothing. A file larger than `max_bytes` returns EOVERFLOW.
export fn load_environment(path: String, max_bytes: Int?) Unit!:
    return msstd_process_load_environment(path, max_bytes)

// Reads the live process directory, preserving OS failures as `Error` values.
export fn working_directory() String!:
    return msstd_process_working_directory()

// Changes the working directory of the whole process, affecting relative paths everywhere.
// A missing path returns ENOENT, a path containing NUL returns EINVAL, and a denied path returns EACCES.
export fn change_directory(path: String) Unit!:
    return msstd_process_change_directory(path)

// Validates a signed 32-bit PID and signal 0..64; the OS decides supported numbers/permissions.
// Signal 0 checks existence; Windows positive PIDs support 0 and forced INT/KILL/TERM termination. A pid that names no process returns ENOENT.
export fn send_signal(pid: Int, signal: Int) Unit!:
    return msstd_process_send_signal(pid, signal)

// Returns the numeric ids of the supplementary groups of the process.
// Windows returns ENOTSUP.
export fn groups() List[Int]!:
    return msstd_process_groups()

// Returns kernel resource counters for this process: CPU times, peak resident size, page faults, block I/O, and context switches.
// Platforms without them return ENOTSUP.
export fn resource_usage() ResourceUsage!:
    return msstd_process_resource_usage()

// Sets mask 0..511 (0777) and returns the previous mask; ENOTSUP on Windows.
export fn umask(mask: Int) Int!:
    return msstd_process_umask(mask)

// Accepts exactly uid, gid, euid, or egid and id 0..2147483647; other inputs return EINVAL.
// Identity changes require OS permission and are ENOTSUP on Windows.
export fn set_identity(kind: String, id: Int) Unit!:
    return msstd_process_set_identity(kind, id)

// Replaces the supplementary group list with the given numeric ids, each 0 through 2147483647. Requires privilege.
// Invalid ids return EINVAL, a lack of privilege returns EACCES, and Windows returns ENOTSUP.
export fn set_groups(groups: List[Int]) Unit!:
    return msstd_process_set_groups(groups)

// Returns the operating system name, processor architecture, and logical CPU count for this host.
export fn system_info() SystemInfo:
    return SystemInfo(
        os: msstd_system_info_os(), architecture: msstd_system_info_architecture(),
        cpu_count: msstd_system_info_cpu_count()
    )

// Returns the host's name as reported by the operating system.
// A name that is not valid UTF-8 returns ENOTSUP.
export fn hostname() String!:
    return msstd_system_hostname()

// Returns the current user's home directory path, from the host's environment or account database.
// A path that is not valid UTF-8 returns ENOTSUP.
export fn home_directory() String!:
    return msstd_system_home_directory()

// Returns the current user's name, numeric ids, home directory, and login shell.
// The shell is empty when the host does not record one, and text that is not valid UTF-8 returns ENOTSUP.
export fn user_info() UserInfo!:
    try msstd_system_user_info_status()
    return ok(
        UserInfo(
            username: msstd_system_user_info_username(),
            uid: msstd_system_user_info_uid(), gid: msstd_system_user_info_gid(),
            home: msstd_system_user_info_home(), shell: msstd_system_user_info_shell()
        )
    )

// Returns one NetworkInterface for every address on every interface, including loopback.
// An interface name that is not valid UTF-8 returns ENOTSUP.
export fn network_interfaces() List[NetworkInterface]!:
    try msstd_system_network_interfaces_status()

    var out: List[NetworkInterface] = []

    for i in 0..msstd_system_network_interfaces_count():
        var family = IpFamily.IPv4
        if msstd_system_network_interfaces_family(i) == 1:
            family = IpFamily.IPv6
        out.append(
            NetworkInterface(
                name: msstd_system_network_interfaces_name(i),
                address: msstd_system_network_interfaces_address(i),
                netmask: msstd_system_network_interfaces_netmask(i), family: family,
                mac: msstd_system_network_interfaces_mac(i),
                internal: msstd_system_network_interfaces_internal(i),
                scope_id: msstd_system_network_interfaces_scope_id(i)
            )
        )

    return ok(out)

// Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
export fn cpus() List[CpuInfo]!:
    try msstd_system_cpus_status()

    var out: List[CpuInfo] = []
    for i in 0..msstd_system_cpus_count():
        out.append(
            CpuInfo(
                model: msstd_system_cpus_model(i),
                speed_mhz: msstd_system_cpus_speed_mhz(i),
                user: msstd_system_cpus_user(i), nice: msstd_system_cpus_nice(i),
                system: msstd_system_cpus_system(i), idle: msstd_system_cpus_idle(i),
                irq: msstd_system_cpus_irq(i)
            )
        )
    return ok(out)

// Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
// A host query failure returns an `Error` describing it.
export fn metrics() SystemMetrics!:
    try msstd_system_metrics_status()
    return ok(
        SystemMetrics(
            total_memory: msstd_system_metrics_total_memory(),
            free_memory: msstd_system_metrics_free_memory(),
            available_memory: msstd_system_metrics_available_memory(),
            uptime: Duration(nanos: msstd_system_metrics_uptime()),
            load_average: [
                msstd_system_metrics_load_average(0),
                msstd_system_metrics_load_average(1),
                msstd_system_metrics_load_average(2)
            ],
            available_parallelism: msstd_system_metrics_available_parallelism()
        )
    )

// Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
// Returns ENOTSUP where the host does not expose it.
export fn os_release() String!:
    return msstd_system_os_release()

// Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
// Returns ENOTSUP where the host does not expose it.
export fn os_version() String!:
    return msstd_system_os_version()

// Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use the target's architecture name.
export fn machine() String!:
    return msstd_system_machine()

// Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
// A pid outside 0 through 2147483647 returns EINVAL, and platforms without priorities return ENOTSUP.
export fn get_priority(pid: Int) Int!:
    return msstd_system_get_priority(pid)

// Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
// Unix uses nice values; Windows maps ranges to native priority classes.
export fn set_priority(pid: Int, priority: Int) Unit!:
    return msstd_system_set_priority(pid, priority)
