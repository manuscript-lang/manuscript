+++
title = "Numbers and booleans"
weight = 3
+++

# Numbers and booleans

`3` is an `Int`, `0.5` a `Float`, `12.50d` a `Decimal`. Conversions are explicit. Booleans are `true` and `false`.

```manuscript
let count = 3
let ratio = 0.5
let price = 12.50d
let active = true
```

Decimal literals need `import Decimal from "@std/decimal.ms"`. Integer literals are `Int`; a fraction or exponent selects `Float`; the `d` suffix selects `Decimal` (`1d` included). See the [grammar](grammar.md#source-characters-and-tokens) for literal forms.

| Type | Representation |
| --- | --- |
| `Int` | Platform-sized signed integer (64 bits on 64-bit targets, 32 bits on 32-bit targets) with checked arithmetic |
| `Float` | IEEE 754 binary64 |
| `Decimal` | Base-10, 34 significant digits, round half to even |
| `Bool` | `true` or `false` |

## Arithmetic and conversion

- Arithmetic operands must have the same numeric type; the result has that type. `%` takes only `Int`.
- Ordering comparisons need matching numeric types; equality follows the [Equal rules](../types/equality-and-hashing.md). The [expression table](expressions.md#operand-and-result-types) is authoritative.
- Int overflow and invalid Int/Decimal operations are programming faults; Float follows the rules below.
- Conversions use the [methods below](#numeric-conversion). Expected types never change a literal's type.
- Integer literals are checked against the signed 64-bit range. `9223372036854775808` is accepted only when directly negated (parentheses do not help).
- A Float literal rounds to binary64; one that rounds to infinity is rejected.
- This guide assumes 64-bit `Int`; 32-bit targets narrow the range.

```manuscript
fn literals() Unit:
    let smallest: Int = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    # Rejected: an Int token does not become Float from context.
    let mismatch: Float = 1
```

## Numeric conversion

| Receiver | Signature/result |
| --- | --- |
| `Int` | `to_float() Float`; `to_decimal() Decimal` |
| `Float` | `truncate_to_int() Optional[Int]` |
| `Decimal` | `to_float() Float`; `truncate_to_int() Optional[Int]` |

Int→Decimal is exact. Int→Float and Decimal→Float round once to nearest binary64, ties to even. `truncate_to_int` drops the fraction toward zero; NaN, infinities, and out-of-range results yield `none` (`1e300.truncate_to_int()` is `none`; Float +2^63 fails, -2^63 converts).

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

`round(places:)` yields a Decimal at a chosen scale; `to_fixed(digits:)` yields text with stable trailing zeros (`25.50d` shows as `"25.50"`). Both return `Result[..., NumberError]` (from `@std/numbers.ms`) and work on the exact value. Negative places round to tens, hundreds, and so on.

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
import Decimal from "@std/decimal.ms"
import NumberError from "@std/numbers.ms"
import expect_equal from "@std/testing.ms"

fn amount_text() Result[String, NumberError]:
    let subtotal = 19.99d * 3d
    let tax = try (subtotal * 0.0825d).round(places: 2)
    let tax_text = try tax.to_fixed(digits: 2)
    let total_text = try (subtotal + tax).to_fixed(digits: 2)
    let padded = try 25.50d.to_fixed(digits: 2)
    return ok("tax {tax_text} total {total_text} padded {padded}")

test "decimal amounts":
    try amount_text() | try expect_equal("tax 4.95 total 64.92 padded 25.50")
```

## Booleans

Booleans drive [if](../control-flow/conditionals.md) and [while](../control-flow/loops.md). Numbers are never implicitly Boolean.

## Durations

`500.milliseconds`, `2.seconds`, and `2.minutes` are `Duration` values; the members work on any `Int` expression. A `Duration` is a signed 64-bit nanosecond count (`2.seconds` is 2,000,000,000), and the members check overflow. Import `duration` from `@std/time.ms` for an exact nanosecond interval.

`Instant` is an opaque monotonic instant with no source constructor, comparable only within one run's clock domain; crossing domains faults. Duration and Instant arithmetic checks overflow ([operator table](expressions.md)). Mixed arithmetic such as `2.seconds + 1` is a type error.
