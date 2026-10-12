+++
title = "Time and system information"
weight = 53
+++

# Time and system information

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use Timestamp for wall-clock time and Duration for a time interval. Access the current wall clock, environment, system information, and random bytes through explicit services supplied by the host.

## `@std/time.ms`

```manuscript
fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, LibraryError]
fn format_timestamp(value: Timestamp) -> String
fn nanoseconds(value: Timestamp) -> Int
fn parse_timestamp(text: String) -> Result[Timestamp, LibraryError]
fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, LibraryError]
fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, LibraryError]
fn unix_seconds(value: Timestamp) -> Int
```

## `@std/system.ms`

## `@std/random.ms`

```manuscript
fn secure_int(entropy: Entropy&Shareable, min: Int, max_exclusive: Int) -> Result[Int, LibraryError]
fn uuid_v4(entropy: Entropy&Shareable) -> Result[String, LibraryError]
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
fn bytes(count: Int) -> Result[Bytes, LibraryError]
```

## Services supplied by the CLI

Process provides `wall_clock: WallClock & Shareable`, `system: System & Shareable`, and `entropy: Entropy & Shareable`.

Timestamp represents wall time and is opaque, immutable, shareable, and comparable for equality. Instant remains a monotonic time value; conversion between them is not implicit. Existing Clock and sleep keep their signatures and error/cancellation rules. Wall-clock changes do not affect monotonic deadlines.

## Timestamp rules

Construction accepts UTC years 1–9999 and nanoseconds 0–999999999. Parsing uses strict RFC 3339: an explicit offset, uppercase T/Z, at most nine fractional digits, and no leap seconds.

Formatting uses UTC. It omits a zero fraction and removes trailing fractional zeroes. `shift` checks the resulting calendar range. `difference` returns `OutOfRange` if its nanosecond result cannot fit in Duration.

There are no Timestamp operators or source constructor. Use the named functions; `unix_seconds` and `nanoseconds` expose the components explicitly.

## System information

SystemInfo has `os: String`, `architecture: String`, and `cpu_count: Int`. This is a native runtime snapshot. CPU count does not reserve resources.

`working_directory` returns the fixed startup directory. `environment` returns `none` if the variable is absent or its value cannot be represented as UTF-8. Process.environment remains a startup snapshot. Importing System grants no environment access; receive a service value explicitly. There is no global chdir or environment mutation API.

## Randomness

`Entropy.bytes` returns exactly the requested number of bytes from Go's crypto/rand. Count must be 0–16777216 per call. It never falls back to a deterministic generator.

`secure_int` samples uniformly from a nonempty interval that includes `min` and excludes `max_exclusive`. Rejection sampling avoids bias, including for interval widths above MaxInt64. `uuid_v4` returns a canonical lowercase RFC 9562 version-4 UUID with the correct variant.

A source fake must return the exact requested byte count. Malformed fake output returns `Failed`.

Timezone and calendar conversion, tickers, seeded generators, and environment mutation remain future work.
