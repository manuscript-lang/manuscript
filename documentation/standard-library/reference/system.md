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
    user: Int
    nice: Int
    system: Int
    idle: Int
    irq: Int
```

### CpuInfo.idle

Cumulative milliseconds this logical CPU spent idle.

```manuscript
idle: Int
```

### CpuInfo.irq

Cumulative milliseconds this logical CPU spent servicing hardware and software interrupts.

```manuscript
irq: Int
```

### CpuInfo.model

Marketing name of the processor, such as `Intel(R) Core(TM) i7`; it can be empty where the host does not report one.

```manuscript
model: String
```

### CpuInfo.nice

Cumulative milliseconds this logical CPU spent running low-priority (niced) user processes.

```manuscript
nice: Int
```

### CpuInfo.speed_mhz

Integer megahertz, not a time interval.

```manuscript
speed_mhz: Int
```

### CpuInfo.system

Cumulative milliseconds this logical CPU spent running kernel code.

```manuscript
system: Int
```

### CpuInfo.user

The user, nice, system, idle, and irq fields are cumulative milliseconds.

```manuscript
user: Int
```

## NetworkInterface {data-api-kind="Record"}

Address and link metadata for one host network interface.

```manuscript
type NetworkInterface:
    name: String
    address: String
    netmask: String
    family: IpFamily
    mac: String
    internal: Bool
    scope_id: Int
```

### NetworkInterface.address

The interface's IP address in textual form, such as `192.168.1.5` or `fe80::1`.

```manuscript
address: String
```

### NetworkInterface.family

The IPv4/IPv6 alternative for the native address record.

```manuscript
family: IpFamily
```

### NetworkInterface.internal

True for a loopback interface, which only reaches the local host.

```manuscript
internal: Bool
```

### NetworkInterface.mac

Hardware address as colon-separated lowercase hexadecimal, or an empty string for interfaces without one such as loopback.

```manuscript
mac: String
```

### NetworkInterface.name

Host name of the interface, such as `eth0` or `lo0`. Interfaces with several addresses appear once per address.

```manuscript
name: String
```

### NetworkInterface.netmask

The address's network mask in the same textual form as `address`, such as `255.255.255.0`.

```manuscript
netmask: String
```

### NetworkInterface.scope_id

The operating system's numeric index for the interface, as used to select an interface for link-local IPv6 addresses.

```manuscript
scope_id: Int
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

### System.cpus

Returns one CpuInfo per logical CPU with its model, clock speed, and cumulative time counters.

```manuscript
fn cpus() -> Result[List[CpuInfo], SystemError]
```

### System.environment

Reads the live variable; absent or non-UTF-8 values return none.

```manuscript
fn environment(name: String) -> Optional[String]
```

### System.get_priority

Returns the scheduling priority of process `pid` (0 means the calling process) as a nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority classes onto this range.
A pid outside 0 through 2147483647 returns InvalidInput, and platforms without priorities return Unsupported.

```manuscript
fn get_priority(pid: Int) -> Result[Int, SystemError]
```

### System.home_directory

Returns the current user's home directory path, from the host's environment or account database.
A path that is not valid UTF-8 returns Unsupported.

```manuscript
fn home_directory() -> Result[String, SystemError]
```

### System.hostname

Returns the host's name as reported by the operating system.
A name that is not valid UTF-8 returns Unsupported.

```manuscript
fn hostname() -> Result[String, SystemError]
```

### System.info

Returns the operating system name, processor architecture, and logical CPU count for this host.

```manuscript
fn info() -> SystemInfo
```

### System.machine

Returns the hardware architecture in `uname -m` style, such as `x86_64`, `aarch64`, or `i686`; other architectures use their Go name.

```manuscript
fn machine() -> Result[String, SystemError]
```

### System.metrics

Returns memory sizes in bytes, host uptime, load averages, and available parallelism in one snapshot.
A host query failure returns the matching SystemError.

```manuscript
fn metrics() -> Result[SystemMetrics, SystemError]
```

### System.network_interfaces

Returns one NetworkInterface for every address on every interface, including loopback.
An interface name that is not valid UTF-8 returns Unsupported.

```manuscript
fn network_interfaces() -> Result[List[NetworkInterface], SystemError]
```

### System.os_release

Returns the kernel release string, such as `6.1.0-18-amd64`, with surrounding whitespace removed.
Returns Unsupported where the host does not expose it.

```manuscript
fn os_release() -> Result[String, SystemError]
```

### System.os_version

Returns the kernel build or version string, such as `#1 SMP Debian`, with surrounding whitespace removed.
Returns Unsupported where the host does not expose it.

```manuscript
fn os_version() -> Result[String, SystemError]
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

### System.user_info

Returns the current user's name, numeric ids, home directory, and login shell.
The shell is empty when the host does not record one, and text that is not valid UTF-8 returns Unsupported.

```manuscript
fn user_info() -> Result[UserInfo, SystemError]
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

### SystemError.AlreadyExists

The host reported that the target already exists.

```manuscript
case AlreadyExists
```

### SystemError.Closed

Reserved for operations on a closed system handle; the current operations do not return it.

```manuscript
case Closed
```

### SystemError.Failed

The host reported another failure while querying or changing system state.

```manuscript
case Failed(message: String)
```

### SystemError.InvalidData

Host data could not be interpreted; reserved for malformed host answers.

```manuscript
case InvalidData
```

### SystemError.InvalidInput

A pid is outside 0 through 2147483647, a priority is outside -20 through 19, or the host rejected an argument.

```manuscript
case InvalidInput
```

### SystemError.LimitExceeded

Reserved for results beyond a configured bound; the current operations do not return it.

```manuscript
case LimitExceeded
```

### SystemError.NotFound

The host reported that the target does not exist.

```manuscript
case NotFound
```

### SystemError.PermissionDenied

The host refused the operation for lack of privilege, such as raising another process's priority.

```manuscript
case PermissionDenied
```

### SystemError.Unsupported

The host or platform cannot provide the value, or the value is not valid UTF-8 and cannot become a String.

```manuscript
case Unsupported
```

### SystemError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name paths.

```manuscript
message: String
```

### SystemError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `system: <reason>`.

```manuscript
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

### SystemInfo.architecture

The processor architecture in Go's naming, such as `amd64`, `arm64`, or `386`.

```manuscript
architecture: String
```

### SystemInfo.cpu_count

Number of logical CPUs the operating system reports as present for this process.

```manuscript
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
    total_memory: Int
    free_memory: Int
    available_memory: Int
    uptime: Duration
    load_average: List[Float]
    available_parallelism: Int
```

### SystemMetrics.available_memory

Estimated physical memory in bytes that new work can use without swapping, including reclaimable caches.

```manuscript
available_memory: Int
```

### SystemMetrics.available_parallelism

Logical processors this process may run on, which can be fewer than `SystemInfo.cpu_count` under CPU affinity limits.

```manuscript
available_parallelism: Int
```

### SystemMetrics.free_memory

Physical memory in bytes that is completely unused; caches count as used, so it is usually smaller than `available_memory`.

```manuscript
free_memory: Int
```

### SystemMetrics.load_average

Three Floats for the 1, 5, and 15 minute system load averages; all 0.0 on Windows.

```manuscript
load_average: List[Float]
```

### SystemMetrics.total_memory

Installed physical memory in bytes.

```manuscript
total_memory: Int
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
    uid: Int
    gid: Int
    home: String
    shell: String
```

### UserInfo.gid

Numeric primary group id of the current user; -1 on Windows, where ids are not numeric.

```manuscript
gid: Int
```

### UserInfo.home

Absolute path of the user's home directory from the account database.

```manuscript
home: String
```

### UserInfo.shell

Path of the user's login shell, or an empty string when the host records none.

```manuscript
shell: String
```

### UserInfo.uid

Numeric user id of the current user; -1 on Windows, where ids are not numeric.

```manuscript
uid: Int
```

### UserInfo.username

Login name of the current user.

```manuscript
username: String
```

## constants {data-api-kind="Function"}

Returns native signal/error/loader/priority constants by name.
Names and values vary by host; missing entries do not imply a portable numeric default.

```manuscript
fn constants() -> Map[String, Int]:
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

