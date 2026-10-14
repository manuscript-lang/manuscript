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

## Random {data-api-kind="Native type"}

Mutable, reproducible SplitMix64 state for simulations and tests; unsuitable for secrets.

```manuscript
type Random:
    fn int(min: Int, max_exclusive: Optional[Int] = none) -> Result[Int, RandomError]:
    fn float() -> Float:
    fn choice[T](values: List[T]) -> Optional[T]:
    fn shuffle[T](values: List[T]) -> List[T]:
```

### Random.choice[T]

Selects an element, or none for an empty list without advancing state.

```manuscript
fn choice[T](values: List[T]) -> Optional[T]:
```

### Random.float

Returns a binary64 value in [0, 1), using the next word's highest 53 bits.

```manuscript
fn float() -> Float:
```

### Random.int

Samples a signed integer in [min, max_exclusive); none uses Int's maximum. InvalidInput reports min >= max_exclusive.

```manuscript
fn int(min: Int, max_exclusive: Optional[Int] = none) -> Result[Int, RandomError]:
```

### Random.shuffle[T]

Returns a fresh shallow Fisher–Yates permutation, preserving the input list.

```manuscript
fn shuffle[T](values: List[T]) -> List[T]:
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

## secure_choice {data-api-kind="Function"}

Selects a secure random element, or none for an empty list without reading entropy.

```manuscript
fn secure_choice[T](entropy: Entropy, values: List[T]) -> Result[Optional[T], RandomError]:
```

## secure_float {data-api-kind="Function"}

Returns a secure binary64 value in [0, 1), using 53 unbiased random bits.

```manuscript
fn secure_float(entropy: Entropy) -> Result[Float, RandomError]:
```

## secure_int {data-api-kind="Function"}

Returns a secure integer at least `min` and below `max_exclusive` when supplied.

```manuscript
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Optional[Int] = none) -> Result[Int, RandomError]:
```

## secure_shuffle {data-api-kind="Function"}

Returns a fresh shallow list in a secure Fisher–Yates random order.

```manuscript
fn secure_shuffle[T](entropy: Entropy, values: List[T]) -> Result[List[T], RandomError]:
```

## seeded {data-api-kind="Function"}

Initializes SplitMix64 from the seed's 64-bit two's-complement representation.

```manuscript
fn seeded(seed: Int) -> Random:
```

## uuid_v4 {data-api-kind="Function"}

Creates a version-4 UUID using the supplied cryptographic entropy source.

```manuscript
fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]:
```

