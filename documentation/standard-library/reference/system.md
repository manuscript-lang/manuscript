+++
title = "system"
+++

# @std/system.ms

Import each required symbol with `import Name from "@std/system.ms"`.

## CpuInfo {data-api-kind="Record"}

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

## NetworkInterface {data-api-kind="Record"}

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

## System {data-api-kind="Interface"}

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

## SystemError {data-api-kind="Alternative"}

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

```manuscript
type SystemInfo:
    os: String
    architecture: String
    cpu_count: Int
```

## SystemMetrics {data-api-kind="Record"}

```manuscript
type SystemMetrics:
    total_memory: Int
    free_memory: Int
    available_memory: Int
    uptime: Duration
    load_average: List[Float]
    available_parallelism: Int
```

## UserInfo {data-api-kind="Record"}

```manuscript
type UserInfo:
    username: String
    uid: Int
    gid: Int
    home: String
    shell: String
```

## constants {data-api-kind="Function"}

```manuscript
fn constants() -> Map[String, Int]:
```

## dev_null {data-api-kind="Function"}

```manuscript
fn dev_null() -> String:
```

## end_of_line {data-api-kind="Function"}

```manuscript
fn end_of_line() -> String:
```

## endianness {data-api-kind="Function"}

```manuscript
fn endianness() -> String:
```

## os_type {data-api-kind="Function"}

```manuscript
fn os_type() -> String:
```

## system {data-api-kind="Function"}

```manuscript
fn system() -> System:
```

