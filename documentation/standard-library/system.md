+++
title = "Time and system information"
weight = 13
+++

# Time and system information

API reference: [time](reference/time.md), [system](reference/system.md), [random](reference/random.md).

Use Timestamp for wall-clock time and Duration for a time interval. Access the current wall clock, environment, system information, and random bytes through explicit services supplied by the host.

## Time value methods

Use `clock().now()` for monotonic instants and receiver methods for existing time values. For example, `2.seconds.to_milliseconds()` returns `2000`, `start.shift(2.seconds).difference(start)` returns `2.seconds`, and `wall_clock().now().to_string()` formats the current UTC timestamp.

| Type | Methods |
| --- | --- |
| Duration | `add(right)`, `subtract(right)`, `multiply(factor)`, `divide(divisor)`, `negate()`, `abs()`, `compare(right)` |
| Duration | `to_nanoseconds()`, `to_microseconds()`, `to_milliseconds()` return Int; `to_seconds()`, `to_minutes()`, `to_hours()` return Float |
| Instant | `shift(duration) -> Instant`, `difference(right) -> Duration`, `compare(right) -> Int` |
| Timestamp | `to_string() -> String`, `unix_seconds() -> Int`, `nanoseconds() -> Int`, `compare(right) -> Int` |
| Timestamp | `shift(duration) -> Result[Timestamp, TimeError]`, `difference(right) -> Result[Duration, TimeError]` |

`duration(nanoseconds)` constructs an exact signed 64-bit interval. Integer unit conversions and division truncate toward zero; floating conversions retain fractional units with binary64 rounding. Arithmetic overflow, division by zero, and negating or taking the absolute value of the minimum Duration fault. Duration methods agree with the existing addition/subtraction operators.

`compare` returns -1, 0, or 1. Instant shifts preserve the clock domain. Comparing or taking a difference between instants from different domains faults, as do overflowing shifts or differences. Timestamp comparison works across its full calendar range without computing a Duration.

This complete example measures an elapsed interval using the existing typed APIs:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {clock, sleep} from "@std/time.ms"
import panic from "@std/faults.ms"

test "measure a typed interval":
    let timer = clock()
    let start = timer.now()
    sleep(1.milliseconds)
    let elapsed = timer.now().difference(start)
    if elapsed.compare(1.milliseconds) < 0: return panic("clock interval")
```

See the [time API reference](reference/time.md) for exact signatures and [numeric and time conversion](../core-language/basics/numbers-and-booleans.md#durations) for Int unit members and operators.

## Services supplied by the CLI

Import `wall_clock()` from `@std/time.ms`, `system()` from `@std/system.ms`, and `entropy()` from `@std/random.ms` to obtain those host services.

Timestamp represents wall time and is opaque, immutable, and comparable for equality. Instant remains a monotonic time value; conversion between them is not implicit. Existing Clock and sleep keep their signatures and error/cancellation rules. Wall-clock changes do not affect monotonic deadlines.

## Timestamp rules

Construction accepts UTC years 1–9999 and nanoseconds 0–999999999. Parsing uses strict RFC 3339: an explicit offset, uppercase T/Z, at most nine fractional digits, and no leap seconds.

Formatting uses UTC. It omits a zero fraction and removes trailing fractional zeroes. `shift` checks the resulting calendar range. `difference` returns `OutOfRange` if its nanosecond result cannot fit in Duration.

Construct timestamps with `timestamp` or `parse_timestamp`; inspect and transform them with receiver methods. `unix_seconds()` and `nanoseconds()` expose whole Unix seconds and the nonnegative fractional nanosecond component. Use `value.to_string()`, `value.shift(duration)`, and `value.difference(right)`.

`Timestamp.format(layout:)` formats UTC using Go's reference-time layout, `Mon Jan 2 15:04:05 MST 2006`. For example, `"2006-01-02"` selects a date and `"2006-01-02T15:04:05.000000000Z07:00"` includes nine fractional digits and a zone. Literal text remains literal; an empty layout formats as empty text. `parse_timestamp_format(text:, layout:)` uses the same layout, defaults a missing zone to UTC, and normalizes an explicit offset to UTC. Empty layouts return `InvalidInput`, malformed text returns `InvalidData`, and normalized years outside 1–9999 return `OutOfRange`. Existing strict RFC3339 parsing and `to_string()` remain unchanged.

An Instant has no calendar origin to format or convert to a Timestamp. Convert elapsed time with `difference(right:) -> Duration`; read `wall_clock()` when a calendar time is needed.

## System information

SystemInfo has `os: String`, `architecture: String`, and `cpu_count: Int`. Each `info()` call returns a native runtime record. OS/architecture identifiers use Go names: supported distributions use `linux`, `darwin`, `windows`, and `amd64`/`arm64`; these are open host identifiers, not a promise that other hosts cannot return another name. `os_type()` returns `Linux`, `Darwin`, or `Windows_NT` on those OSes and the Go OS name otherwise. `endianness()` returns exactly `LE` or `BE`. NetworkInterface.family is exactly `IPv4` or `IPv6`. CPU count does not reserve resources.

`working_directory` on the native root returns the live process working directory and faults if the OS lookup fails; the fallible ProcessControl query returns a domain error. `temporary_directory` queries the host temp root without checking or creating it; filesystem temporary-directory factories [create resources](filesystem.md#directories-and-metadata). `environment` returns `none` if the variable is absent or its value cannot be represented as UTF-8. The CLI `environment()` accessor returns a startup snapshot. Importing System supplies its interface; calling the imported `system()` accessor obtains the service. The imported ProcessControl service provides explicit process-wide directory and environment mutation; see [process control](process.md#current-process-control).

## Randomness

`Entropy.bytes` returns exactly the requested number of bytes from the operating system’s cryptographic random source. Count must be 0–16777216 per call. It never falls back to a deterministic generator.

`secure_int` samples uniformly from a nonempty interval that includes `min` and excludes `max_exclusive`. Rejection sampling avoids bias, including for interval widths above MaxInt64. `uuid_v4` returns a canonical lowercase RFC 9562 version-4 UUID with the correct variant.

A source fake must return the exact requested byte count. Malformed fake output returns `Failed`.

`secure_float(entropy:)` samples 53 unbiased bits and returns a binary64 value in `[0, 1)`. `secure_choice(entropy:, values:)` returns an optional original element; an empty input returns `ok(none)` without reading entropy. `secure_shuffle` uses Fisher–Yates and returns a fresh shallow List. Input storage is unchanged and referenced payloads remain shared. Empty and singleton shuffles read no entropy. All secure helpers retain the supplied source's original error payload; malformed byte counts return `RandomError.Failed`.

For repeatable simulations or tests, `seeded(seed:)` creates a mutable `Random`, with `int`, `float`, `choice`, and `shuffle` methods. This generator is not cryptographic. Its SplitMix64 sequence adds `0x9e3779b97f4a7c15`, applies xor/right-shift 30 and multiply `0xbf58476d1ce4e5b9`, xor/right-shift 27 and multiply `0x94d049bb133111eb`, then xor/right-shift 31; all arithmetic wraps modulo 2^64. Seeds use their two's-complement bit representation. Float draws use the highest 53 bits divided by 2^53; integer draws reject the incomplete residue cycle to avoid modulo bias. Identical seeds and serial call sequences give identical results across targets.

Generator aliases share state. Native word draws are synchronized, but concurrent composite calls can interleave their draws; serialize calls when reproducible ordering matters. Choice returns original payloads, and shuffle returns fresh shallow storage. Empty choices and empty/singleton shuffles consume no state. Signed integer bounds include `min` and exclude `max_exclusive`; omitted or `none` upper bounds use Int's maximum. A negative upper bound is valid when greater than `min`. Invalid ranges return `InvalidInput` without advancing the generator. Cancellation unwinds and can follow partial state or entropy consumption; no rollback is implied.

For delayed and repeating callbacks, use [Scheduler](../concurrency/scheduling.md).

## Native system behavior

Architecture names include `amd64` and `arm64`. `metrics.available_parallelism` reports usable processors, including Linux affinity and Windows processor groups. CpuInfo user/nice/system/idle/irq are cumulative integer milliseconds (fractional milliseconds are truncated); irq includes hardware and software interrupts. speed_mhz is integer megahertz with the fractional part truncated, not a duration. `ProcessControl.cpu_usage` and ResourceUsage CPU fields use microseconds. SystemMetrics memory fields use bytes and uptime is host boot time represented as Duration with whole-second native resolution; [process uptime](process.md#process-time-and-accounting) has a different origin.

CPU, memory, uptime, and OS release information use native queries. Windows load averages are three zeros. User shell comes from native macOS user records or local Linux passwd entries; it is empty on Windows or when no local Linux shell is available.

`system.constants()` exposes native signal, error, dynamic-loader, and priority names. Names and values are host-specific; missing keys must be handled rather than replaced by an assumed number. `set_priority` accepts PID `0..2147483647` and priority `-20..19` (lower numbers mean higher priority). Unix uses nice values. Windows maps `-20..-15`, `-14..-8`, `-7..-1`, `0..9`, `10..18`, and `19` to highest/high/above-normal/normal/below-normal/low classes; `get_priority` returns their representative values `-20`, `-14`, `-7`, `0`, `10`, and `19`. It does not round-trip every accepted Int. Process mutation and platform limits are described in [process control](process.md#current-process-control).
