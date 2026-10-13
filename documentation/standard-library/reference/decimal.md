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
    fn to_float64() -> Float64:
    fn truncate_to_int() -> Optional[Int]:
    fn truncate_to_int64() -> Optional[Int64]:
    fn round(places: Int, mode: Optional[RoundingMode] = none) -> Result[Decimal, NumberError]:
    fn to_fixed(digits: Int, mode: Optional[RoundingMode] = none) -> Result[String, NumberError]:
```

### Decimal.round

Rounds exactly to a multiple of `10^-places`, without converting to Float.
Places range from -6144 through 6176; negative places round tens, hundreds, etc.
Invalid places return InvalidInput; an unrepresentable result returns OutOfRange.
Omitted or `none` mode selects HalfEven. This does not preserve trailing zeros or change arithmetic.

```manuscript
fn round(places: Int, mode: Optional[RoundingMode] = none) -> Result[Decimal, NumberError]:
```

### Decimal.to_fixed

Rounds exactly and prints plain decimal notation with exactly `digits` fractional digits.
Digits range from 0 through 6176; invalid digits return InvalidInput.
HalfEven is the default; rounded zero has no minus sign. Trailing zeros are retained.

```manuscript
fn to_fixed(digits: Int, mode: Optional[RoundingMode] = none) -> Result[String, NumberError]:
```

### Decimal.to_float64

Rounds directly to IEEE binary64, without a default Float intermediate.

```manuscript
fn to_float64() -> Float64:
```

### Decimal.truncate_to_int64

Truncates exactly toward zero, returning none outside signed64.

```manuscript
fn truncate_to_int64() -> Optional[Int64]:
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

