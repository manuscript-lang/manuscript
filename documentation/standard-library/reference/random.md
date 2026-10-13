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

