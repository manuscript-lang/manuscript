+++
title = "Time and system information"
weight = 13
+++

# Time and system information

API reference: [time](reference/time.md), [system](reference/system.md), [random](reference/random.md).

Use Timestamp for wall-clock time and Duration for a time interval. Access the current wall clock, environment, system information, and random bytes through explicit services supplied by the host.

## Time value methods

Use receiver methods for existing time values. For example, `2.seconds.to_milliseconds()` returns `2000`, `start.shift(2.seconds).difference(start)` returns `2.seconds`, and `wall_clock().now().to_string()` formats the current UTC timestamp.

| Type | Methods |
| --- | --- |
| Duration | `add(right)`, `subtract(right)`, `multiply(factor)`, `divide(divisor)`, `negate()`, `abs()`, `compare(right)` |
| Duration | `to_nanoseconds()`, `to_microseconds()`, `to_milliseconds()` return Int; `to_seconds()`, `to_minutes()`, `to_hours()` return Float |
| Instant | `shift(duration) -> Instant`, `difference(right) -> Duration`, `compare(right) -> Int` |
| Timestamp | `to_string() -> String`, `unix_seconds() -> Int`, `nanoseconds() -> Int`, `compare(right) -> Int` |
| Timestamp | `shift(duration) -> Result[Timestamp, TimeError]`, `difference(right) -> Result[Duration, TimeError]` |

`duration(nanoseconds)` constructs an exact signed 64-bit interval. Integer unit conversions and division truncate toward zero; floating conversions retain fractional units with binary64 rounding. Arithmetic overflow, division by zero, and negating or taking the absolute value of the minimum Duration fault. Duration methods agree with the existing addition/subtraction operators.

`compare` returns -1, 0, or 1. Instant shifts preserve the clock domain. Comparing or taking a difference between instants from different domains faults, as do overflowing shifts or differences. Timestamp comparison works across its full calendar range without computing a Duration.

See the [time API reference](reference/time.md) for exact signatures and [numeric and time conversion](../core-language/basics/numbers-and-booleans.md#durations) for Int unit members and operators.

## Services supplied by the CLI

Import `wall_clock()` from `@std/time.ms`, `system()` from `@std/system.ms`, and `entropy()` from `@std/random.ms` to obtain those host services.

Timestamp represents wall time and is opaque, immutable, and comparable for equality. Instant remains a monotonic time value; conversion between them is not implicit. Existing Clock and sleep keep their signatures and error/cancellation rules. Wall-clock changes do not affect monotonic deadlines.

## Timestamp rules

Construction accepts UTC years 1–9999 and nanoseconds 0–999999999. Parsing uses strict RFC 3339: an explicit offset, uppercase T/Z, at most nine fractional digits, and no leap seconds.

Formatting uses UTC. It omits a zero fraction and removes trailing fractional zeroes. `shift` checks the resulting calendar range. `difference` returns `OutOfRange` if its nanosecond result cannot fit in Duration.

Construct timestamps with `timestamp` or `parse_timestamp`; inspect and transform them with receiver methods. `unix_seconds()` and `nanoseconds()` expose whole Unix seconds and the nonnegative fractional nanosecond component. Use `value.to_string()`, `value.shift(duration)`, and `value.difference(right)`.

## System information

SystemInfo has `os: String`, `architecture: String`, and `cpu_count: Int`. This is a native runtime snapshot. CPU count does not reserve resources.

`working_directory` on the native root returns the live process working directory. `environment` returns `none` if the variable is absent or its value cannot be represented as UTF-8. The CLI `environment()` accessor returns a startup snapshot. Importing System supplies its interface; calling the imported `system()` accessor obtains the service. The imported ProcessControl service provides explicit process-wide directory and environment mutation; see [process control](process.md#current-process-control).

## Randomness

`Entropy.bytes` returns exactly the requested number of bytes from the operating system’s cryptographic random source. Count must be 0–16777216 per call. It never falls back to a deterministic generator.

`secure_int` samples uniformly from a nonempty interval that includes `min` and excludes `max_exclusive`. Rejection sampling avoids bias, including for interval widths above MaxInt64. `uuid_v4` returns a canonical lowercase RFC 9562 version-4 UUID with the correct variant.

A source fake must return the exact requested byte count. Malformed fake output returns `Failed`.

For delayed and repeating callbacks, use [Scheduler](../concurrency/scheduling.md).

## Native system behavior

Architecture names include `amd64` and `arm64`. `metrics.available_parallelism` reports usable processors, including Linux affinity and Windows processor groups. CPU records use milliseconds for accounting; `ProcessControl.cpu_usage` uses microseconds.

CPU, memory, uptime, and OS release information use native queries. Windows load averages are three zeros. User shell comes from native macOS user records or local Linux passwd entries; it is empty on Windows or when no local Linux shell is available.

`system.constants()` exposes native signal, error, dynamic-loader, and priority names. Values are host-specific; only supported constants are exported. Process mutation and platform limits are described in [process control](process.md#current-process-control).
