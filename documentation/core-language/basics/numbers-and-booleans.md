+++
title = "Numbers and booleans"
weight = 3
+++

# Numbers and booleans

A number literal has a specific type: `3` is an Int, `0.5` is a Float, and `12.50d` is a Decimal. Convert explicitly when a function needs another numeric type. Boolean values are `true` and `false`.

```manuscript
let count = 3
let ratio = 0.5
let price = 12.50d
let active = true
```

Decimal literals require `import Decimal from "@std/decimal.ms"`; Decimal is an imported standard type with compiler-supported literals and arithmetic. Integer literals infer `Int`; a fraction or exponent without a suffix selects `Float`; the `d` suffix selects `Decimal`, including integer-shaped literals such as `1d`. The [source grammar](grammar.md#source-characters-and-tokens) specifies decimal digits, fractions, exponents, and rejected literal forms.

| Type | Representation |
| --- | --- |
| `Int` | Platform-sized signed integer (Go `int`: 64 bits on 64-bit targets, 32 bits on 32-bit targets) with checked arithmetic |
| `Float` | IEEE 754 binary64 |
| `Decimal` | Base-10, 34 significant digits, round half to even |
| `Bool` | `true` or `false` |

## Arithmetic and conversion

Numeric conversions are explicit. Int overflow and invalid Int/Decimal operations produce programming faults; Float operations follow the non-finite rules below. An inferred local type does not authorize an implicit conversion at a call boundary. The [numeric conversion rules](#numeric-conversion) below define the callable conversions.

Arithmetic operands must have the same exact numeric type, and the result has that type. Unary signs retain their operand type. `%` accepts only `Int` operands. Ordering comparisons accept matching numeric types and return `Bool`; equality additionally follows the [Equal rules](../types/equality-and-hashing.md). The [expression table](expressions.md#operand-and-result-types) is authoritative for operator typing.

`Int` is the target's Go `int`; this guide assumes 64 bits (on 32-bit targets ranges shrink to signed 32 bits and an out-of-range literal fails the Go build). Integer literals are checked against the signed 64-bit range at compile time. `9223372036854775808` is accepted only as a directly negated literal, giving `-9223372036854775808` (parentheses around it do not help). A Float literal rounds to binary64 (ties to even); one that rounds to infinity is rejected. Expected types do not change literal types.

```manuscript
fn literals() -> Unit:
    let smallest: Int = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    # Rejected: an Int token does not become Float from context.
    let mismatch: Float = 1
```

## Numeric conversion

| Receiver | Signature/result |
| --- | --- |
| `Int` | `to_float() -> Float`; `to_decimal() -> Decimal` |
| `Float` | `truncate_to_int() -> Optional[Int]` |
| `Decimal` | `to_float() -> Float`; `truncate_to_int() -> Optional[Int]` |

Int→Decimal is exact. Int→Float and Decimal→Float round once to nearest binary64, ties to even. Decimal→Float may produce signed infinity or signed zero under the Float rules. Truncation discards the fractional part toward zero, then checks the mathematical integer against the target platform’s `Int` range before conversion. NaN, infinities, or an out-of-range integer yield `none`.

For example, `1e300.truncate_to_int()` is `none`. Float +2^63 cannot convert to Int, while Float -2^63 can.

## Runtime numeric outcomes

### Int

Int addition, subtraction, multiplication, and unary negation fault when the mathematical result is outside the target `Int` range (signed 64 bits on 64-bit targets). Division truncates toward zero. Remainder has the sign of the dividend (or is zero), satisfying `a = (a / b) * b + a % b` mathematically. A zero divisor faults for both operations. Minimum Int divided by -1 faults, while Minimum Int modulo -1 is zero. Unary negation of Minimum Int faults. Thus `-7 / 2` is -3 and `-7 % 3` is -1.

Int `/` and `%` faults name the operator and the invalid right operand. Division overflow also gives both operands and the target `Int` result range. These remain programming faults, while BigInt division returns its declared Result error.

### Float

Float operations round each result to binary64 (ties to even) with no fused multiply-add or reassociation. Overflow gives signed infinity; division by zero follows IEEE (infinity, or NaN for zero/zero); invalid arithmetic gives NaN without a fault; underflow gives a subnormal or signed zero. Every ordering comparison with NaN is false, `==` is false and `!=` true even against itself, and positive and negative zero are equal. Source literals still reject infinity. See [string formatting](text-and-bytes.md#deterministic-formatting) for non-finite spellings.

### Decimal

Decimal is finite base-ten arithmetic with 34 significant digits. Its representable values are `c × 10^q`, with signed integer coefficient `c` of at most 34 digits and quantum exponent `q` between -6176 and 6111 inclusive. This gives a largest adjusted exponent of 6144, a smallest normal adjusted exponent of -6143, and subnormals down to `1e-6176d`. Decimal has no NaN or infinity; all zero encodings have the same numerical value and format as `0`.

For each Decimal operator:

1. Compute the exact mathematical result. Division by zero faults.
2. For a nonzero magnitude with adjusted decimal exponent `e`, choose quantum `q = max(e - 33, -6176)`.
3. Round the exact value divided by `10^q` to an integer coefficient, ties to even. If it has 35 digits, shift one exact trailing zero into `q`.
4. Require an equivalent representation with at most 34 coefficient digits and `q` in range. Otherwise overflow faults.

An arithmetic overflow fault identifies the Decimal operator and operands and states the maximum finite magnitude after rounding. These diagnostics preserve the fault category and the existing arithmetic limits.

There is one rounding step per operator. Do not round intermediate coefficients, reassociate operators, or saturate to the maximum finite value. Underflow produces a subnormal or zero without fault. `1d / 3d` is `0.3333333333333333333333333333333333d`. Equality and ordering compare exact stored numerical values, ignoring scale and trailing zeroes.

Decimal literals are accepted only when their exact mathematical value is representable without rounding. Insignificant leading/trailing coefficient zeroes do not count against precision: `1.00d` is exact. A literal requiring 35 significant digits, such as `1.2345678901234567890123456789012345d`, or lying outside the representable grid is a compile error. `1e6144d` and `1e-6176d` are accepted; `1e6145d` and `1e-6177d` are rejected. Unary-negative literal checking follows the same magnitude rules. Runtime conversion and arithmetic are separate from source literal acceptance.

The following calculation stays in `Decimal` because each numeric literal has a `d` suffix:

```manuscript
let price = 100d
let percent = 15d
let discounted = price * (1d - percent / 100d)
```

Use ordinary validation when invalid numbers are expected inputs. [Expected failures](../errors/results.md) shows how to return a domain error before calculating a discount; [programming faults](../errors/faults.md) explains invariant failures.

#### Scale rounding and fixed places

Use `round(places:)` when a calculation needs a Decimal at a chosen scale, and `to_fixed(digits:)` when output needs stable trailing zeros. Both return `Result[..., NumberError]` from `@std/numbers.ms` and operate on the exact stored value without a Float conversion. `round(places: 2)` rounds to hundredths; negative places round to tens, hundreds, and larger powers of ten. Decimal values still ignore scale: use `to_fixed(digits: 2)` to display `25.50d` as `"25.50"`.

Omitting `mode` or supplying `none` chooses `RoundingMode.HalfEven`. Import `RoundingMode` from `@std/decimal.ms` to choose another mode:

| Mode | Rule | `2.5d` at zero places | `-2.5d` at zero places |
| --- | --- | --- | --- |
| `HalfEven` | Nearest; a tie chooses an even coefficient | `2d` | `-2d` |
| `HalfAwayFromZero` | Nearest; a tie rounds away from zero | `3d` | `-3d` |
| `TowardZero` | Discard the fractional coefficient | `2d` | `-2d` |
| `Floor` | Toward negative infinity | `2d` | `-3d` |
| `Ceil` | Toward positive infinity | `3d` | `-2d` |

`round` accepts places from -6144 through 6176. It returns `InvalidInput` for other places, and `OutOfRange` if the rounded number cannot be represented exactly as a Decimal. It never rounds again to fit the 34-digit arithmetic context. `to_fixed` accepts digits from 0 through 6176, returning `InvalidInput` otherwise. It uses plain notation even for large values, retains exactly the requested fractional digits, and prints any rounded zero without a minus sign. Neither method changes the receiver or the rounding of arithmetic operators.

For amounts with two fractional places, this example explicitly rounds tax before adding it. Choose the scale, rounding mode, and rounding stage required by your application; Decimal does not impose a currency policy. Scaled Int cents are another option when all values and arithmetic fit the checked Int range.

Save the following as `cents.ms` and run `ms test cents.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Decimal from "@std/decimal.ms"
import NumberError from "@std/numbers.ms"
import panic from "@std/faults.ms"

fn amount_text() -> Result[String, NumberError]:
    let subtotal = 19.99d * 3d
    let tax = try (subtotal * 0.0825d).round(places: 2)
    let tax_text = try tax.to_fixed(digits: 2)
    let total_text = try (subtotal + tax).to_fixed(digits: 2)
    let padded = try 25.50d.to_fixed(digits: 2)
    return ok("tax {tax_text} total {total_text} padded {padded}")

test "decimal amounts":
    let text = try amount_text()
    if text != "tax 4.95 total 64.92 padded 25.50":
        return panic("unexpected amount text")
```

## Booleans

A Boolean value controls an [if statement](../control-flow/conditionals.md) or [while loop](../control-flow/loops.md). There is no numeric-to-Boolean conversion implied by using a number as a condition.

## Durations

`milliseconds`, `seconds`, and `minutes` are Int members: `500.milliseconds` and `2.seconds` have type `Duration`. They also work on nonliteral Int expressions; `Instant` represents a monotonic clock instant. They are used by timeouts and deadlines.

`Duration` is a signed 64-bit count of nanoseconds. The three unit members work on any Int and multiply by 1,000,000, 1,000,000,000, or 60,000,000,000 with overflow checks. Import `duration` from `@std/time.ms` for an exact nanosecond interval. Integer conversions truncate toward zero; floating ones keep fractions at binary64 precision. `Instant` is an opaque monotonic instant with no source constructor, comparable only within one run's clock domain; crossing domains faults. Duration and Instant arithmetic check overflow ([operator table](expressions.md)).

Duration and Instant overflow diagnostics name the arithmetic operation, the operands in nanoseconds, and the signed 64-bit result range; multiplication factors and divisors remain dimensionless. Duration `divide` names an invalid divisor. Unit-member conversion and Duration `negate`/`abs` faults give the allowed input range and original value. The arithmetic, rounding, clock-domain, and cancellation rules remain unchanged.

`2.seconds` is 2,000,000,000 nanoseconds. Unsupported unit names and mixed arithmetic such as `2.seconds + 1` are type errors.

See time value methods for Duration, Instant, and Timestamp operations.
