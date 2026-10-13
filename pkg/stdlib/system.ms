# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Duration from "@std/time.ms"

# Read-only host details and selected controls for the current operating system.
export interface System:
    # Reads the live variable; absent or non-UTF-8 values return none.
    fn environment(name: String) -> Optional[String]
    fn info() -> SystemInfo
    # Reads the live native directory; an OS query failure faults because this API has no Result.
    # A host service constructed with an explicit directory retains that base.
    fn working_directory() -> String
    fn hostname() -> Result[String, SystemError]
    fn home_directory() -> Result[String, SystemError]
    # Queries the host temp root without creating or checking a directory; non-UTF-8 returns Unsupported.
    fn temporary_directory() -> Result[String, SystemError]
    fn user_info() -> Result[UserInfo, SystemError]
    fn network_interfaces() -> Result[List[NetworkInterface], SystemError]
    fn cpus() -> Result[List[CpuInfo], SystemError]
    fn metrics() -> Result[SystemMetrics, SystemError]
    fn os_release() -> Result[String, SystemError]
    fn os_version() -> Result[String, SystemError]
    fn machine() -> Result[String, SystemError]
    fn get_priority(pid: Int) -> Result[Int, SystemError]
    # Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
    # Unix uses nice values; Windows maps ranges to native priority classes.
    fn set_priority(pid: Int, priority: Int) -> Result[Unit, SystemError]

# Operating system and processor architecture for the current host.
export type SystemInfo:
    # Native Go OS identifier, such as linux, darwin, or windows; an open host identifier set.
    os: String
    architecture: String
    cpu_count: Int

# User name, numeric identity, home directory, and login shell.
export type UserInfo:
    username: String
    uid: Int
    gid: Int
    home: String
    shell: String

# Address and link metadata for one host network interface.
export type NetworkInterface:
    name: String
    address: String
    netmask: String
    # Exactly `IPv4` or `IPv6` for native address records.
    family: String
    mac: String
    internal: Bool
    scope_id: Int

# Model, integer MHz speed (fractional MHz truncated), and cumulative integer millisecond
# counters for one logical CPU. irq includes hardware and software interrupt time.
export type CpuInfo:
    model: String
    # Integer megahertz, not a time interval.
    speed_mhz: Int
    # The user, nice, system, idle, and irq fields are cumulative milliseconds.
    user: Int
    nice: Int
    system: Int
    idle: Int
    irq: Int

# Host measurements: memory fields are bytes; load_average is 1/5/15-minute load
# (three zeros on Windows); available_parallelism is a usable logical-processor count.
export type SystemMetrics:
    total_memory: Int
    free_memory: Int
    available_memory: Int
    # Host boot uptime as a Duration with whole-second native resolution; not process uptime.
    uptime: Duration
    load_average: List[Float]
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
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)

impl Error for SystemError:
    fn message() -> String:

# Returns system information and controls for the current host.
export fn system() -> System:
