+++
title = "Time and system information"
weight = 53
+++

# Time and system information

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/time.ms`

```text
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

```text
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Int) -> Result[Int, LibraryError]
fn uuid_v4(entropy: Entropy) -> Result[String, LibraryError]
```

## WallClock operations

```text
fn now() -> Timestamp
```

## System operations

```text
fn info() -> SystemInfo
fn working_directory() -> String
fn environment(name: String) -> Optional[String]
```

## Entropy operations

```text
fn bytes(count: Int) -> Result[Bytes, LibraryError]
```

CLI Process adds `wall_clock: WallClock`, `system: System`, and `entropy: Entropy`. Timestamp is opaque immutable/shareable/equal wall time; Instant remains monotonic and cannot be converted implicitly. Clock and existing sleep retain their previous signatures and cancellation/domain behavior. Wall-clock changes never alter monotonic deadlines.

Timestamp construction requires years 1–9999 in UTC and nanoseconds 0–999999999. Parsing requires strict RFC 3339 with explicit offset, uppercase T/Z, 0–9 fractional digits and no leap seconds. Format uses UTC, omits zero fractions and trims trailing fraction zeros. Shift checks calendar range; difference returns OutOfRange if its nanosecond result cannot fit Duration. Timestamp introduces no operators or source constructor; unix_seconds/nanoseconds expose explicit components.

SystemInfo fields are `os: String`, `architecture: String`, `cpu_count: Int`. Info is a native runtime snapshot; CPU count is not a resource reservation. Working_directory is the fixed startup directory. Environment lookup returns none for absence or a value unrepresentable as UTF-8. The original Process.environment remains a startup snapshot; imports do not grant environment access. There is no global chdir or environment mutation API.

Entropy bytes returns exactly count bytes from crypto/rand, requires count 0–16777216 per call, and never falls back to a deterministic PRNG. Secure_int uses unbiased rejection sampling over a nonempty half-open Int interval, including widths exceeding MaxInt64. UUID output is canonical lowercase RFC 9562 version 4 with the correct variant. Source entropy fakes must honor exact lengths; malformed fake output returns Failed. Timezone/calendar conversion, tickers, seeded PRNGs, and environment mutation remain future additions.
