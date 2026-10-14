+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy {data-api-kind="Interface"}

A source of cryptographically secure random bytes.

```manuscript
interface Entropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]
```

### Entropy.bytes

Returns exactly `count` unpredictable bytes, with `count` from 0 through 16 MiB (16777216).
A negative or larger count returns InvalidInput; a source failure returns Failed. The operating system source observes task cancellation between 64 KiB chunks.

```manuscript
fn bytes(count: Int) -> Result[Bytes, RandomError]
```

## RandomError {data-api-kind="Alternative"}

Errors returned when random input is invalid or entropy generation fails.

```manuscript
type RandomError:
    case InvalidInput
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for RandomError:
    fn message() -> String:
```

### RandomError.Failed

The entropy source could not produce bytes, or returned a different number of bytes than requested.

```manuscript
case Failed(message: String)
```

### RandomError.InvalidInput

The requested byte count is negative or above 16 MiB, or `secure_int` was given `min` not below `max_exclusive`.

```manuscript
case InvalidInput
```

### RandomError.LimitExceeded

Reserved for requests that exceed a configured random-generation budget; the current operations do not return it.

```manuscript
case LimitExceeded
```

### RandomError.Failed.message

The source's failure text, which `message()` returns verbatim.

```manuscript
message: String
```

### RandomError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `random: <reason>`.

```manuscript
fn message() -> String:
```

## entropy {data-api-kind="Function"}

Returns the operating system's cryptographic entropy source.

```manuscript
fn entropy() -> Entropy:
```

## secure_int {data-api-kind="Function"}

Returns a secure integer at least `min` and below `max_exclusive` when supplied.

```manuscript
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Optional[Int] = none) -> Result[Int, RandomError]:
```

## uuid_v4 {data-api-kind="Function"}

Creates a version-4 UUID using the supplied cryptographic entropy source.

```manuscript
fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]:
```

