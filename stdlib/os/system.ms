import (
    MetricsSnapshot from "@std/internal/system.ms",
    Duration from "@std/time.ms",
    IpFamily from "@std/net/ip.ms",
    msstd_system_endianness,
    msstd_system_end_of_line,
    msstd_system_dev_null,
    msstd_system_os,
    msstd_system_constants,
    msstd_system_info,
    msstd_system_user_info,
    msstd_system_network_interfaces,
    msstd_system_cpus,
    msstd_system_metrics,
    msstd_system_hostname,
    msstd_system_machine,
    msstd_system_os_release,
    msstd_system_os_version,
    msstd_process_available_memory,
    msstd_process_constrained_memory,
    msstd_process_elapsed,
    msstd_process_memory_usage from "@std/internal/system.ms",
)

// The operating system family the program was built for. A host outside the three named families reads as `Other`.
export enum Os:
    Linux  // The program runs on a Linux kernel of any distribution.
    Macos  // The program runs on Apple macOS, which `uname` reports as Darwin.
    Windows  // The program runs on Microsoft Windows, where numeric user ids read as -1.
    Other  // The host is outside the three named families, such as a BSD.

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

// Operating system and processor architecture for the current host.
export type SystemInfo:
    // Operating system identifier, such as linux, darwin, or windows; an open host identifier set. `os()` names the supported families as an enum.
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

// The byte order of the host's native integers.
export enum Endianness:
    Little  // The least significant byte comes first, as on x86-64 and AArch64.
    Big  // The most significant byte comes first.

// Returns the host's native byte order.
export fn endianness() Endianness:
    if msstd_system_endianness() == "BE": return Endianness.Big

    return Endianness.Little

// Returns the host's line-ending sequence.
export fn end_of_line() String:
    return msstd_system_end_of_line()

// Returns the conventional null-device path for the host.
export fn dev_null() String:
    return msstd_system_dev_null()

// Returns the operating system family this program runs on.
export fn os() Os:
    let code = msstd_system_os()
    if code == 0: return Os.Linux
    if code == 1: return Os.Macos
    if code == 2: return Os.Windows

    return Os.Other

// Returns native signal/error/loader/priority constants by name.
// Names and values vary by host; missing entries do not imply a portable numeric default.
export fn constants() Map[String, Int]:
    return msstd_system_constants()

// Returns the memory limit in bytes imposed on this process by its Linux cgroup, or 0 when no limit applies or the platform has no such limit.
// ms: effect std.system.read
export fn constrained_memory() Int!:
    return msstd_process_constrained_memory()

// Returns bytes available to new allocations: the host's available memory, reduced to the remaining headroom when a Linux cgroup memory limit applies.
// ms: effect std.system.read
export fn available_memory() Int!:
    return msstd_process_available_memory()

// Returns heap and resident memory statistics for this process, in bytes.
// ms: effect std.system.read
export fn memory_usage() MemoryUsage!:
    return msstd_process_memory_usage()

// Returns elapsed Duration since runtime initialization, rather than host boot.
// ms: effect std.system.read
export fn uptime() Duration!:
    return msstd_process_elapsed()

// Returns the operating system name, processor architecture, and logical CPU count for this host.
// ms: effect std.system.read
export fn system_info() SystemInfo:
    return msstd_system_info()

// Returns the host's name as reported by the operating system.
// A name that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.system.read
export fn hostname() String!:
    return msstd_system_hostname()

// Returns the current user's name, numeric ids, home directory, and login shell.
// The shell is empty when the host does not record one, and text that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.system.read
export fn user_info() UserInfo!:
    return msstd_system_user_info()

// Returns one NetworkInterface for every address on every interface, including loopback.
// An interface name that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.system.read
export fn network_interfaces() List[NetworkInterface]!:
    return msstd_system_network_interfaces()

// Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
// ms: effect std.system.read
export fn cpus() List[CpuInfo]!:
    return msstd_system_cpus()

// Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
// A host query failure returns an `Error` describing it.
// ms: effect std.system.read
export fn metrics() SystemMetrics!:
    let snapshot = try msstd_system_metrics()
    return ok(
        SystemMetrics(
            total_memory: snapshot.total_memory,
            free_memory: snapshot.free_memory,
            available_memory: snapshot.available_memory,
            uptime: Duration(nanos: snapshot.uptime_nanos),
            load_average: [
                snapshot.load_1, snapshot.load_5, snapshot.load_15
            ],
            available_parallelism: snapshot.available_parallelism
        )
    )

// Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
// Returns ENOTSUP where the host does not expose it.
// ms: effect std.system.read
export fn os_release() String!:
    return msstd_system_os_release()

// Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
// Returns ENOTSUP where the host does not expose it.
// ms: effect std.system.read
export fn os_version() String!:
    return msstd_system_os_version()

// Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use the target's architecture name.
// ms: effect std.system.read
export fn machine() String!:
    return msstd_system_machine()
