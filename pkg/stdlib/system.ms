# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Duration from "@std/time.ms"

# Read-only host details and selected controls for the current operating system.
export interface System:
    fn environment(name: String) -> Optional[String]
    fn info() -> SystemInfo
    fn working_directory() -> String
    fn hostname() -> Result[String, SystemError]
    fn home_directory() -> Result[String, SystemError]
    fn temporary_directory() -> Result[String, SystemError]
    fn user_info() -> Result[UserInfo, SystemError]
    fn network_interfaces() -> Result[List[NetworkInterface], SystemError]
    fn cpus() -> Result[List[CpuInfo], SystemError]
    fn metrics() -> Result[SystemMetrics, SystemError]
    fn os_release() -> Result[String, SystemError]
    fn os_version() -> Result[String, SystemError]
    fn machine() -> Result[String, SystemError]
    fn get_priority(pid: Int) -> Result[Int, SystemError]
    fn set_priority(pid: Int, priority: Int) -> Result[Unit, SystemError]

# Operating system and processor architecture for the current host.
export type SystemInfo:
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
    family: String
    mac: String
    internal: Bool
    scope_id: Int

# Model, speed, and cumulative time counters for one logical CPU.
export type CpuInfo:
    model: String
    speed_mhz: Int
    user: Int
    nice: Int
    system: Int
    idle: Int
    irq: Int

# Host memory, uptime, load, and available parallelism measurements.
export type SystemMetrics:
    total_memory: Int
    free_memory: Int
    available_memory: Int
    uptime: Duration
    load_average: List[Float]
    available_parallelism: Int

# Returns `little` or `big` for the host's native byte order.
export fn endianness() -> String:

# Returns the host's line-ending sequence.
export fn end_of_line() -> String:

# Returns the conventional null-device path for the host.
export fn dev_null() -> String:

# Returns the host operating-system family.
export fn os_type() -> String:

# Returns operating-system constants by name.
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
