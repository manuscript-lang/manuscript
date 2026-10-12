# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"
import Duration from "@std/time.ms"
import Optional from "@std/optional.ms"

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

export type SystemInfo:
    os: String
    architecture: String
    cpu_count: Int

export type UserInfo:
    username: String
    uid: Int
    gid: Int
    home: String
    shell: String

export type NetworkInterface:
    name: String
    address: String
    netmask: String
    family: String
    mac: String
    internal: Bool
    scope_id: Int

export type CpuInfo:
    model: String
    speed_mhz: Int
    user: Int
    nice: Int
    system: Int
    idle: Int
    irq: Int

export type SystemMetrics:
    total_memory: Int
    free_memory: Int
    available_memory: Int
    uptime: Duration
    load_average: List[Float]
    available_parallelism: Int

export fn endianness() -> String:

export fn end_of_line() -> String:

export fn dev_null() -> String:

export fn os_type() -> String:

export fn constants() -> Map[String, Int]:

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

export fn system() -> System:
