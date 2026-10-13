+++
title = "decimal"
+++

# @std/decimal.ms

Import each required symbol with `import Name from "@std/decimal.ms"`.

## Decimal {data-api-kind="Native type"}

An exact decimal value. Conversions are explicit because binary floats may round.

```manuscript
type Decimal:
    fn to_float() -> Float:
    fn truncate_to_int() -> Optional[Int]:
    fn abs() -> Decimal:
    fn compare(right: Decimal) -> Int:
    fn floor_to_int() -> Optional[Int]:
    fn ceil_to_int() -> Optional[Int]:
    fn round_to_int() -> Optional[Int]:
    fn round(places: Int, mode: Optional[RoundingMode] = none) -> Result[Decimal, NumberError]:
    fn to_fixed(digits: Int, mode: Optional[RoundingMode] = none) -> Result[String, NumberError]:
```

### Decimal.abs

Returns the nonnegative exact magnitude without changing this value.

```manuscript
fn abs() -> Decimal:
```

### Decimal.ceil_to_int

Rounds upward exactly; returns none when the integer is outside signed 64-bit range.

```manuscript
fn ceil_to_int() -> Optional[Int]:
```

### Decimal.compare

Returns -1, 0, or 1 by comparing exact decimal values without converting to Float.

```manuscript
fn compare(right: Decimal) -> Int:
```

### Decimal.floor_to_int

Rounds downward exactly; returns none when the integer is outside signed 64-bit range.

```manuscript
fn floor_to_int() -> Optional[Int]:
```

### Decimal.round

Rounds exactly to a multiple of `10^-places`, without converting to Float.
Places range from -6144 through 6176; negative places round tens, hundreds, etc.
Invalid places return InvalidInput; an unrepresentable result returns OutOfRange.
Omitted or `none` mode selects HalfEven. This does not preserve trailing zeros or change arithmetic.

```manuscript
fn round(places: Int, mode: Optional[RoundingMode] = none) -> Result[Decimal, NumberError]:
```

### Decimal.round_to_int

Rounds exactly to the nearest integer, with ties choosing the even integer.
Returns none when the rounded integer is outside signed 64-bit range.

```manuscript
fn round_to_int() -> Optional[Int]:
```

### Decimal.to_fixed

Rounds exactly and prints plain decimal notation with exactly `digits` fractional digits.
Digits range from 0 through 6176; invalid digits return InvalidInput.
HalfEven is the default; rounded zero has no minus sign. Trailing zeros are retained.

```manuscript
fn to_fixed(digits: Int, mode: Optional[RoundingMode] = none) -> Result[String, NumberError]:
```

## RoundingMode {data-api-kind="Alternative"}

How a Decimal rounds to a multiple of the requested power of ten.

```manuscript
type RoundingMode:
    case HalfEven
    case HalfAwayFromZero
    case TowardZero
    case Floor
    case Ceil
```

### RoundingMode.Ceil

Rounds toward positive infinity.

```manuscript
case Ceil
```

### RoundingMode.Floor

Rounds toward negative infinity.

```manuscript
case Floor
```

### RoundingMode.HalfAwayFromZero

Nearest value; an exact tie rounds away from zero.

```manuscript
case HalfAwayFromZero
```

### RoundingMode.HalfEven

Nearest value; an exact tie chooses the even coefficient.

```manuscript
case HalfEven
```

### RoundingMode.TowardZero

Discards the fractional coefficient toward zero.

```manuscript
case TowardZero
```

