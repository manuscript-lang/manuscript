import IpFamily from "@std/net.ms"
# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Duration from "@std/time.ms"

# Read-only host details and selected controls for the current operating system.
export interface System:
    # Reads the live variable; absent or non-UTF-8 values return none.
    fn environment(name: String) -> Optional[String]
    # Returns the operating system name, processor architecture, and logical CPU count for this host.
    fn info() -> SystemInfo
    # Reads the live native directory; an OS query failure faults because this API has no Result.
    # A host service constructed with an explicit directory retains that base.
    fn working_directory() -> String
    # Returns the host's name as reported by the operating system.
    # A name that is not valid UTF-8 returns Unsupported.
    fn hostname() -> Result[String, SystemError]
    # Returns the current user's home directory path, from the host's environment or account database.
    # A path that is not valid UTF-8 returns Unsupported.
    fn home_directory() -> Result[String, SystemError]
    # Queries the host temp root without creating or checking a directory; non-UTF-8 returns Unsupported.
    fn temporary_directory() -> Result[String, SystemError]
    # Returns the current user's name, numeric ids, home directory, and login shell.
    # The shell is empty when the host does not record one, and text that is not valid UTF-8 returns Unsupported.
    fn user_info() -> Result[UserInfo, SystemError]
    # Returns one NetworkInterface for every address on every interface, including loopback.
    # An interface name that is not valid UTF-8 returns Unsupported.
    fn network_interfaces() -> Result[List[NetworkInterface], SystemError]
    # Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.
    fn cpus() -> Result[List[CpuInfo], SystemError]
    # Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
    # A host query failure returns the matching SystemError.
    fn metrics() -> Result[SystemMetrics, SystemError]
    # Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    fn os_release() -> Result[String, SystemError]
    # Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
    # Returns Unsupported where the host does not expose it.
    fn os_version() -> Result[String, SystemError]
    # Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use their Go name.
    fn machine() -> Result[String, SystemError]
    # Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
    # A pid outside 0 through 2147483647 returns InvalidInput, and platforms without priorities return Unsupported.
    fn get_priority(pid: Int) -> Result[Int, SystemError]
    # Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
    # Unix uses nice values; Windows maps ranges to native priority classes.
    fn set_priority(pid: Int, priority: Int) -> Result[Unit, SystemError]

# Operating system and processor architecture for the current host.
export type SystemInfo:
    # Native Go OS identifier, such as linux, darwin, or windows; an open host identifier set.
    os: String
    # The processor architecture in Go's naming, such as `amd64`, `arm64`, or `386`.
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
export fn endianness() -> String:

# Returns the host's line-ending sequence.
export fn end_of_line() -> String:

# Returns the conventional null-device path for the host.
export fn dev_null() -> String:

# Returns Linux, Darwin, or Windows_NT on the supported hosts; other hosts use their Go OS name.
export fn os_type() -> String:

# Returns native signal/error/loader/priority constants by name.
# Names and values vary by host; missing entries do not imply a portable numeric default.
export fn constants() -> Map[String, Int]:

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
    fn message() -> String:

# Returns system information and controls for the current host.
export fn system() -> System:
