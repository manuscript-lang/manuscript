+++
title = "Numbers and booleans"
weight = 3
+++

# Numbers and booleans

`3` is an `Int`, `0.5` a `Float`, `12.50d` a `Decimal`. Conversions are explicit. Booleans are `True` and `False`.

```manuscript
let count = 3
let ratio = 0.5
let price = 12.50d
let active = True
```

Decimal literals need `from "@std/decimal.ms" import Decimal`. Integer literals are `Int`; a fraction or exponent selects `Float`; the `d` suffix selects `Decimal` (`1d` included). See the [grammar](grammar.md#source-characters-and-tokens) for literal forms.

| Type | Representation |
| --- | --- |
| `Int` | Signed 64-bit integer with checked arithmetic; `Int64` is the same type |
| `Int8`, `Int16`, `Int32` | Signed integers of that width with checked arithmetic; `Int64` is another name for `Int` |
| `Float` | IEEE 754 binary64; `Float64` is another name for it |
| `Float32` | IEEE 754 binary32; every operation rounds to binary32 |
| `Decimal` | Base-10, 34 significant digits, round half to even |
| `Bool` | `True` or `False` |

## Arithmetic and conversion

- Arithmetic operands must have the same numeric type; the result has that type. `%` takes integers of the same width.
- Ordering comparisons need matching numeric types; equality follows the [Equal rules](../types/equality-and-hashing.md). The [expression table](expressions.md#operand-and-result-types) is authoritative.
- Int overflow and invalid Int/Decimal operations are programming faults; Float follows the rules below.
- Conversions between existing values use the [methods below](#numeric-conversion). A literal can take a sized type from context, as described below.
- Integer literals are checked against the signed 64-bit range. `9223372036854775808` is accepted only when directly negated (parentheses do not help).
- A Float literal rounds to binary64; one that rounds to infinity is rejected.
- A literal takes a sized type from an expected type or from the other operand of an operator: `let x: Int8 = 100` and `x / 2` both type the literal as `Int8`. It must fit that type (`let x: Int8 = 128` is rejected), and a negated literal is checked after negation (`-128` fits `Int8`). A literal never changes kind: `let x: Float32 = 1` is rejected.
- The default types remain `Int`/`Int64` and `Float`/`Float64`; choose a sized type explicitly when storage or precision matters.

```manuscript
def literals() -> Unit:
    let smallest: Int = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    # Rejected: an Int token does not become Float from context.
    let mismatch: Float = 1
```

## Sized numbers

`Int8`, `Int16`, `Int32` and `Float32` occupy 1, 2, 4 and 4 bytes in lists, records, optionals, alternatives, maps and sets; locals and arguments keep full-width registers, so only storage shrinks. A `List[Int8]` of fifty million elements takes one eighth of the memory of a `List[Int]`. Arithmetic needs both operands to have the same type, so `Int8 + Int32` is rejected, and an `Int8` operation that leaves -128 to 127 faults:

```manuscript
def sized() -> Unit:
    let a: Int8 = 100
    let wide: Int32 = 2000000000
    let ratio: Float32 = 0.1
    # Faults: 200 does not fit Int8.
    let b = a + a
    # Rejected: operand types differ.
    let c = a + wide
```

`Float32` operations round once to binary32, so `0.1 + 0.2` is `0.3` for `Float32` and `0.30000000000000004` for `Float`. Sized types are not yet accepted as list indexes, `match` subjects or JSON values. Convert them explicitly to `Int` or `Float` at those boundaries; see [numeric conversion](#numeric-conversion), [list indexing](../types/collections.md), [matching literals](../control-flow/pattern-matching.md#matching-literals), and the [JSON API](../../standard-library/reference/json.md).

## Numeric conversion

| Receiver | Signature/result |
| --- | --- |
| `Int` | `to_float() -> Float`; `to_decimal() -> Decimal` |
| `Float` | `truncate_to_int() -> Optional[Int]` |
| Any sized integer or `Int` | `to_int8()`, `to_int16()`, `to_int32()`, `to_int64()`, `to_int()`, `to_float32()`, `to_float64()`, `to_float()`, `to_decimal()` |
| `Float`, `Float32` | `to_float32()`, `to_float64()`, `to_float()` (`Float32` only), `truncate_to_int() -> Optional[Int]` |
| `Decimal` | `to_float() -> Float`; `truncate_to_int() -> Optional[Int]` |

`to_intN()` returns the wider or equal type directly when every value fits (`Int8.to_int32()`) and `Optional` of it otherwise (`Int32.to_int8()` is `none` for 70000); conversions to a float round to the nearest value, ties to even. Int→Decimal is exact. Int→Float and Decimal→Float round once to nearest binary64, ties to even. `truncate_to_int` drops the fraction toward zero; NaN, infinities, and out-of-range results yield `none` (`1e300.truncate_to_int()` is `none`; Float +2^63 fails, -2^63 converts).

`abs()` and `sign()` are methods on every integer and float type, so no cast is needed: `abs()` returns the receiver's own type (`Int8` `-128` has no absolute value and faults like any overflow), integer `sign()` returns `Int` (-1, 0 or 1), and float `sign()` returns the receiver's type with zeros and NaN unchanged. `@std/math.ms` has no `abs`, `sign` or `to_float32` functions; the methods are the one spelling. `min`, `max`, `min_of` and `max_of` already accept any `Comparable` width.

## Runtime numeric outcomes

### Int

- `+`, `-`, `*`, and unary `-` fault when the result leaves the `Int` range.
- `/` truncates toward zero; `%` takes the dividend's sign, so `a = (a / b) * b + a % b`. `-7 / 2` is -3 and `-7 % 3` is -1.
- A zero divisor faults. Minimum Int `/ -1` faults; Minimum Int `% -1` is zero.

These are programming faults; BigInt division returns a Result error.

### Float

Each operation rounds to binary64 (ties to even) with no fused multiply-add or reassociation. Overflow gives signed infinity; division by zero gives infinity (NaN for 0/0); invalid arithmetic gives NaN with no fault; underflow gives a subnormal or signed zero. Comparisons with NaN are false (`!=` is true, even against itself); positive and negative zero are equal. See [string formatting](text-and-bytes.md#deterministic-formatting) for non-finite spellings.

### Decimal

Values are `c × 10^q`: a signed coefficient `c` of at most 34 digits and exponent `q` from -6176 to 6111 (largest adjusted exponent 6144, smallest normal -6143, subnormals down to `1e-6176d`). There is no NaN or infinity, and every zero formats as `0`.

Each operator:

1. Compute the exact mathematical result. Division by zero faults.
2. For a nonzero magnitude with adjusted decimal exponent `e`, choose quantum `q = max(e - 33, -6176)`.
3. Round the exact value divided by `10^q` to an integer coefficient, ties to even. If it has 35 digits, shift one exact trailing zero into `q`.
4. Require an equivalent representation with at most 34 coefficient digits and `q` in range. Otherwise overflow faults.

Each operator rounds once: no intermediate rounding, reassociation, or saturation. Underflow gives a subnormal or zero. `1d / 3d` is `0.3333333333333333333333333333333333d`. Equality and ordering compare numeric values, ignoring scale.

A Decimal literal must be exactly representable: `1.00d` is fine, but 35 significant digits (`1.2345678901234567890123456789012345d`) or an out-of-grid value is a compile error. `1e6144d` and `1e-6176d` are accepted; `1e6145d` and `1e-6177d` are not.

Every literal needs the `d` suffix to stay `Decimal`:

```manuscript
let price = 100d
let percent = 15d
let discounted = price * (1d - percent / 100d)
```

Validate expected bad input with [expected failures](../errors/results.md); see [programming faults](../errors/faults.md) for invariants.

#### Scale rounding and fixed places

`round(places:)` yields a Decimal at a chosen scale; `to_fixed(digits:)` yields text with stable trailing zeros (`25.50d` shows as `"25.50"`). Both return `Result[..., NumberError]` (from `@std/math.ms`) and work on the exact value. Negative places round to tens, hundreds, and so on.

The default `mode` is `RoundingMode.HalfEven`; import `RoundingMode` from `@std/decimal.ms` for others:

| Mode | Rule | `2.5d` at zero places | `-2.5d` at zero places |
| --- | --- | --- | --- |
| `HalfEven` | Nearest; a tie chooses an even coefficient | `2d` | `-2d` |
| `HalfAwayFromZero` | Nearest; a tie rounds away from zero | `3d` | `-3d` |
| `TowardZero` | Discard the fractional coefficient | `2d` | `-2d` |
| `Floor` | Toward negative infinity | `2d` | `-3d` |
| `Ceil` | Toward positive infinity | `3d` | `-2d` |

- `round` accepts places -6144 to 6176, else `InvalidInput`; `OutOfRange` if the result is not exactly representable. It never re-rounds to 34 digits.
- `to_fixed` accepts digits 0 to 6176, else `InvalidInput`. It uses plain notation, keeps exactly the requested digits, and prints a rounded zero without a minus sign.

Decimal imposes no currency policy; scaled Int cents also work. This example rounds tax before adding it. Run it with `ms test cents.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/decimal.ms" import Decimal
from "@std/math.ms" import NumberError
from "@std/testing.ms" import expect_equal

def amount_text() -> Result[String, NumberError]:
    let subtotal = 19.99d * 3d
    let tax = try (subtotal * 0.0825d).round(places: 2)
    let tax_text = try tax.to_fixed(digits: 2)
    let total_text = try (subtotal + tax).to_fixed(digits: 2)
    let padded = try 25.50d.to_fixed(digits: 2)
    return ok(f"tax {tax_text} total {total_text} padded {padded}")

test "decimal amounts":
    try amount_text() | try expect_equal("tax 4.95 total 64.92 padded 25.50")
```

## Booleans

Booleans drive [if](../control-flow/conditionals.md) and [while](../control-flow/loops.md). Numbers are never implicitly Boolean.

## Durations

`500.milliseconds`, `2.seconds`, and `2.minutes` are `Duration` values; the members work on any `Int` expression. A `Duration` is a signed 64-bit nanosecond count (`2.seconds` is 2,000,000,000), and the members check overflow. Import `duration` from `@std/time.ms` for an exact nanosecond interval.

`Instant` is an opaque monotonic instant with no source constructor, comparable only within one run's clock domain; crossing domains faults. Duration and Instant arithmetic checks overflow ([operator table](expressions.md)). Mixed arithmetic such as `2.seconds + 1` is a type error.
