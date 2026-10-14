import IpFamily from "@std/net.ms"
# Canonical standard-library declarations. Implementations are native.

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

# documentation documentation/standard-library/services.md
# +++
# title = "External services"
# weight = 2
# +++
#
# # External services
#
# A capability is an object that lets a function use an external service, such as storage, networking, a clock, or a model client. A helper can receive that object as an ordinary parameter, making its dependency visible and allowing tests to supply a source implementation.
#
# Applications can also import host accessors such as `filesystem()`, `network()`, or `clock()` from their standard modules. They return the services associated with the current execution; [Command-line programs](cli.md#importing-host-services) defines the complete accessor set and lifetime rules. Accessors do not require dependency declarations on the calling function. Importing a contract type alone does not obtain a service.
#
# Manuscript does not enforce a per-function authority set or manifest permissions. Native host services provide their normal OS access. Explicit parameters are a composition and testing technique, rather than the only route to a service. Tooling cannot claim to enumerate all reachable authority from parameter names alone; callbacks and stored values can retain services as well.
#
# ## Sharing an implementation
#
# A network or storage implementation can receive concurrent calls. Its mutable internal state must be synchronized. References do not extend a resource's open lifetime; methods coordinate active calls with close.
#
# See [sharing data](../concurrency/sharing.md).
# end-documentation

# documentation documentation/standard-library/system.md
# +++
# title = "Time and system information"
# weight = 13
# +++
#
# # Time and system information
#
# API reference: [time](reference/time.md), [system](reference/system.md), [random](reference/random.md).
#
# Use Timestamp for wall-clock time and Duration for a time interval. Access the current wall clock, environment, system information, and random bytes through explicit services supplied by the host.
#
# ## Time value methods
#
# Use `clock().now()` for monotonic instants and receiver methods for existing time values. For example, `2.seconds.to_milliseconds()` returns `2000`, `start.shift(2.seconds).difference(start)` returns `2.seconds`, and `wall_clock().now().to_string()` formats the current UTC timestamp.
#
# Method names and signatures are in the [`@std/time.ms` reference](reference/time.md).
#
# `duration(nanoseconds)` constructs an exact signed 64-bit interval. Integer unit conversions and division truncate toward zero; floating conversions retain fractional units with binary64 rounding. Arithmetic overflow, division by zero, and negating or taking the absolute value of the minimum Duration fault. Duration methods agree with the existing addition/subtraction operators.
#
# `compare` returns -1, 0, or 1. Instant shifts preserve the clock domain. Comparing or taking a difference between instants from different domains faults, as do overflowing shifts or differences. Timestamp comparison works across its full calendar range without computing a Duration.
#
# This complete example measures an elapsed interval using the existing typed APIs:
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {clock, sleep} from "@std/time.ms"
# import panic from "@std/faults.ms"
#
# test "measure a typed interval":
#     let timer = clock()
#     let start = timer.now()
#     sleep(1.milliseconds)
#     let elapsed = timer.now().difference(start)
#     if elapsed.compare(1.milliseconds) < 0: return panic("clock interval")
# ```
#
# See the [time API reference](reference/time.md) for exact signatures and [numeric and time conversion](../core-language/basics/numbers-and-booleans.md#durations) for Int unit members and operators.
#
# ## Services supplied by the CLI
#
# Import `wall_clock()` from `@std/time.ms`, `system()` from `@std/system.ms`, and `entropy()` from `@std/random.ms` to obtain those host services.
#
# Timestamp represents wall time and is opaque, immutable, and comparable for equality. Instant remains a monotonic time value; conversion between them is not implicit. Existing Clock and sleep keep their signatures and error/cancellation rules. Wall-clock changes do not affect monotonic deadlines.
#
# ## Timestamp rules
#
# Construction accepts UTC years 1–9999 and nanoseconds 0–999999999. Parsing uses strict RFC 3339: an explicit offset, uppercase T/Z, at most nine fractional digits, and no leap seconds.
#
# Formatting uses UTC. It omits a zero fraction and removes trailing fractional zeroes. `shift` checks the resulting calendar range. `difference` returns `OutOfRange` if its nanosecond result cannot fit in Duration.
#
# Construct timestamps with `timestamp` or `parse_timestamp`; inspect and transform them with receiver methods. `unix_seconds()` and `nanoseconds()` expose whole Unix seconds and the nonnegative fractional nanosecond component. Use `value.to_string()`, `value.shift(duration)`, and `value.difference(right)`.
#
# ## System information
#
# SystemInfo has `os: String`, `architecture: String`, and `cpu_count: Int`. Each `info()` call returns a native runtime record. OS/architecture identifiers use Go names: supported distributions use `linux`, `darwin`, `windows`, and `amd64`/`arm64`; these are open host identifiers, not a promise that other hosts cannot return another name. `os_type()` returns `Linux`, `Darwin`, or `Windows_NT` on those OSes and the Go OS name otherwise. `endianness()` returns exactly `LE` or `BE`. NetworkInterface.family is `IpFamily.IPv4` or `IpFamily.IPv6` from `@std/net.ms`; its `text()` returns the prior spelling. CPU count does not reserve resources.
#
# `working_directory` on the native root returns the live process working directory and faults if the OS lookup fails; the fallible ProcessControl query returns a domain error. `temporary_directory` queries the host temp root without checking or creating it; filesystem temporary-directory factories [create resources](filesystem.md#directories-and-metadata). `environment` returns `none` if the variable is absent or its value cannot be represented as UTF-8. The CLI `environment()` accessor returns a startup snapshot. Importing System supplies its interface; calling the imported `system()` accessor obtains the service. The imported ProcessControl service provides explicit process-wide directory and environment mutation; see [process control](process.md#current-process-control).
#
# ## Randomness
#
# `Entropy.bytes` returns exactly the requested number of bytes from the operating system’s cryptographic random source. Count must be 0–16777216 per call. It never falls back to a deterministic generator.
#
# `secure_int` samples uniformly from a nonempty interval that includes `min` and excludes `max_exclusive`. Rejection sampling avoids bias, including for interval widths above MaxInt64. `uuid_v4` returns a canonical lowercase RFC 9562 version-4 UUID with the correct variant.
#
# A source fake must return the exact requested byte count. Malformed fake output returns `Failed`.
#
# For delayed and repeating callbacks, use [Scheduler](../concurrency/scheduling.md).
#
# ## Native system behavior
#
# Architecture names include `amd64` and `arm64`. `metrics.available_parallelism` reports usable processors, including Linux affinity and Windows processor groups. CpuInfo user/nice/system/idle/irq are cumulative integer milliseconds (fractional milliseconds are truncated); irq includes hardware and software interrupts. speed_mhz is integer megahertz with the fractional part truncated, not a duration. `ProcessControl.cpu_usage` and ResourceUsage CPU fields use microseconds. SystemMetrics memory fields use bytes and uptime is host boot time represented as Duration with whole-second native resolution; [process uptime](process.md#process-time-and-accounting) has a different origin.
#
# CPU, memory, uptime, and OS release information use native queries. Windows load averages are three zeros. User shell comes from native macOS user records or local Linux passwd entries; it is empty on Windows or when no local Linux shell is available.
#
# `system.constants()` exposes native signal, error, dynamic-loader, and priority names. Names and values are host-specific; missing keys must be handled rather than replaced by an assumed number. `set_priority` accepts PID `0..2147483647` and priority `-20..19` (lower numbers mean higher priority). Unix uses nice values. Windows maps `-20..-15`, `-14..-8`, `-7..-1`, `0..9`, `10..18`, and `19` to highest/high/above-normal/normal/below-normal/low classes; `get_priority` returns their representative values `-20`, `-14`, `-7`, `0`, `10`, and `19`. It does not round-trip every accepted Int. Process mutation and platform limits are described in [process control](process.md#current-process-control).
# end-documentation
