+++
title = "Time and system information"
weight = 53
+++

# Time and system information

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use Timestamp for wall-clock time and Duration for a time interval. Access the current wall clock, environment, system information, and random bytes through explicit services supplied by the host.

## `@std/time.ms`

```manuscript
fn duration(nanoseconds: Int) -> Duration
fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]
fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]
fn clock() -> Clock
fn wall_clock() -> WallClock
fn sleep(duration: Duration) -> Unit
```

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

See the [time API reference](../reference/time.md) for exact signatures and [numeric and time conversion](../data-and-io/operations.md#numeric-and-time-conversion) for Int unit members and operators.

## `@std/system.ms`

## `@std/random.ms`

```manuscript
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Optional[Int]) -> Result[Int, RandomError]
fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]
```

## WallClock operations

```manuscript
fn now() -> Timestamp
```

## System operations

```manuscript
fn info() -> SystemInfo
fn working_directory() -> String
fn environment(name: String) -> Optional[String]
```

## Entropy operations

```manuscript
fn bytes(count: Int) -> Result[Bytes, RandomError]
```

## Services supplied by the CLI

Import `wall_clock()` from `@std/time.ms`, `system()` from `@std/system.ms`, and `entropy()` from `@std/random.ms` to obtain those host services.

Timestamp represents wall time and is opaque, immutable, and comparable for equality. Instant remains a monotonic time value; conversion between them is not implicit. Existing Clock and sleep keep their signatures and error/cancellation rules. Wall-clock changes do not affect monotonic deadlines.

## Timestamp rules

Construction accepts UTC years 1–9999 and nanoseconds 0–999999999. Parsing uses strict RFC 3339: an explicit offset, uppercase T/Z, at most nine fractional digits, and no leap seconds.

Formatting uses UTC. It omits a zero fraction and removes trailing fractional zeroes. `shift` checks the resulting calendar range. `difference` returns `OutOfRange` if its nanosecond result cannot fit in Duration.

Construct timestamps with `timestamp` or `parse_timestamp`; inspect and transform them with receiver methods. `unix_seconds()` and `nanoseconds()` expose whole Unix seconds and the nonnegative fractional nanosecond component. Use `value.to_string()`, `value.shift(duration)`, and `value.difference(right)`.

## System information

SystemInfo has `os: String`, `architecture: String`, and `cpu_count: Int`. This is a native runtime snapshot. CPU count does not reserve resources.

`working_directory` on the native root returns the live process working directory. `environment` returns `none` if the variable is absent or its value cannot be represented as UTF-8. The CLI `environment()` accessor returns a startup snapshot. Importing System supplies its interface; calling the imported `system()` accessor obtains the service. The imported ProcessControl service provides explicit process-wide directory and environment mutation; see [host contracts](node-host.md).

## Randomness

`Entropy.bytes` returns exactly the requested number of bytes from Go's crypto/rand. Count must be 0–16777216 per call. It never falls back to a deterministic generator.

`secure_int` samples uniformly from a nonempty interval that includes `min` and excludes `max_exclusive`. Rejection sampling avoids bias, including for interval widths above MaxInt64. `uuid_v4` returns a canonical lowercase RFC 9562 version-4 UUID with the correct variant.

A source fake must return the exact requested byte count. Malformed fake output returns `Failed`.

Timezone and calendar conversion, tickers, seeded generators, and environment mutation remain future work.
