+++
title = "system"
+++

# @std/system.ms

Import each required symbol with `import Name from "@std/system.ms"`.

## CpuInfo {data-api-kind="Record"}

Model, integer MHz speed (fractional MHz truncated), and cumulative integer millisecond
counters for one logical CPU. irq includes hardware and software interrupt time.

```manuscript
type CpuInfo:
    model: String
    speed_mhz: Int
    user: Int64
    nice: Int64
    system: Int64
    idle: Int64
    irq: Int64
```

### CpuInfo.speed_mhz

Integer megahertz, not a time interval.

```manuscript
speed_mhz: Int
```

### CpuInfo.user

The user, nice, system, idle, and irq fields are cumulative milliseconds.

```manuscript
user: Int64
```

## NetworkInterface {data-api-kind="Record"}

Address and link metadata for one host network interface.

```manuscript
type NetworkInterface:
    name: String
    address: String
    netmask: String
    family: String
    mac: String
    internal: Bool
    scope_id: Int
```

### NetworkInterface.family

Exactly `IPv4` or `IPv6` for native address records.

```manuscript
family: String
```

## System {data-api-kind="Interface"}

Read-only host details and selected controls for the current operating system.

```manuscript
interface System:
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
```

### System.environment

Reads the live variable; absent or non-UTF-8 values return none.

```manuscript
fn environment(name: String) -> Optional[String]
```

### System.set_priority

Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
Unix uses nice values; Windows maps ranges to native priority classes.

```manuscript
fn set_priority(pid: Int, priority: Int) -> Result[Unit, SystemError]
```

### System.temporary_directory

Queries the host temp root without creating or checking a directory; non-UTF-8 returns Unsupported.

```manuscript
fn temporary_directory() -> Result[String, SystemError]
```

### System.working_directory

Reads the live native directory; an OS query failure faults because this API has no Result.
A host service constructed with an explicit directory retains that base.

```manuscript
fn working_directory() -> String
```

## SystemError {data-api-kind="Alternative"}

Errors returned when a requested host operation is unavailable or denied.

```manuscript
type SystemError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)
```

```manuscript
impl Error for SystemError:
    fn message() -> String:
```

## SystemInfo {data-api-kind="Record"}

Operating system and processor architecture for the current host.

```manuscript
type SystemInfo:
    os: String
    architecture: String
    cpu_count: Int
```

### SystemInfo.os

Native Go OS identifier, such as linux, darwin, or windows; an open host identifier set.

```manuscript
os: String
```

## SystemMetrics {data-api-kind="Record"}

Host measurements: memory fields are bytes; load_average is 1/5/15-minute load
(three zeros on Windows); available_parallelism is a usable logical-processor count.

```manuscript
type SystemMetrics:
    total_memory: Int64
    free_memory: Int64
    available_memory: Int64
    uptime: Duration
    load_average: List[Float64]
    available_parallelism: Int
```

### SystemMetrics.uptime

Host boot uptime as a Duration with whole-second native resolution; not process uptime.

```manuscript
uptime: Duration
```

## UserInfo {data-api-kind="Record"}

User name, numeric identity, home directory, and login shell.

```manuscript
type UserInfo:
    username: String
    uid: Int64
    gid: Int64
    home: String
    shell: String
```

## constants {data-api-kind="Function"}

Returns native signal/error/loader/priority constants by name.
Names and values vary by host; missing entries do not imply a portable numeric default.

```manuscript
fn constants() -> Map[String, Int64]:
```

## dev_null {data-api-kind="Function"}

Returns the conventional null-device path for the host.

```manuscript
fn dev_null() -> String:
```

## end_of_line {data-api-kind="Function"}

Returns the host's line-ending sequence.

```manuscript
fn end_of_line() -> String:
```

## endianness {data-api-kind="Function"}

Returns exactly `LE` or `BE` for the host's native byte order.

```manuscript
fn endianness() -> String:
```

## os_type {data-api-kind="Function"}

Returns Linux, Darwin, or Windows_NT on the supported hosts; other hosts use their Go OS name.

```manuscript
fn os_type() -> String:
```

## system {data-api-kind="Function"}

Returns system information and controls for the current host.

```manuscript
fn system() -> System:
```

