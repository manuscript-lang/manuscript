+++
title = "Numbers and booleans"
weight = 9
+++

# Numbers and booleans

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A number literal has a specific type: `3` is an Int, `0.5` is a Float, and `12.50d` is a Decimal. Convert explicitly when a function needs another numeric type. Boolean values are `true` and `false`.

```text
let count = 3
let ratio = 0.5
let price = 12.50d
let active = true
```

Decimal literals require `import Decimal from "@std/decimal.ms"`; Decimal is an imported standard type with compiler-supported literals and arithmetic. Integer literals infer `Int`; a fraction or exponent without a suffix selects `Float`; the `d` suffix selects `Decimal`, including integer-shaped literals such as `1d`. The [source grammar](grammar.md#source-characters-and-tokens) specifies decimal digits, fractions, exponents, and rejected literal forms.

| Type | Representation |
| --- | --- |
| `Int` | Signed 64-bit integer with checked arithmetic |
| `Float` | IEEE 754 binary64 |
| `Decimal` | Base-10, 34 significant digits, round half to even |
| `Bool` | `true` or `false` |

## Arithmetic and conversion

Numeric conversions are explicit. Int overflow and invalid Int/Decimal operations produce programming faults; Float operations follow the non-finite rules below. An inferred local type does not authorize an implicit conversion at a call boundary. The [minimum data API](../../standard-library/data-and-io/operations.md#numeric-and-time-conversion) defines the callable conversions.

Arithmetic operands must have the same exact numeric type, and the result has that type. Unary signs retain their operand type. `%` accepts only `Int` operands. Ordering comparisons accept matching numeric types and return `Bool`; equality additionally follows the [Equal rules](../types/equality-and-hashing.md). The [expression table](expressions.md#operand-and-result-types) is authoritative for operator typing.

Integer literals are checked against the signed 64-bit range at compile time. The magnitude `9223372036854775808` is accepted only as a directly negated integer literal, giving `-9223372036854775808`; parentheses immediately around that literal do not change the check. The positive literal and magnitudes outside either signed boundary are rejected. A Float literal rounds to binary64 using nearest, ties to even; one whose rounded magnitude would be infinite is rejected. Expected numeric types do not change literal types.

```text
fn literals() -> Unit:
    let smallest: Int = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    # Rejected: an Int token does not become Float from context.
    let mismatch: Float = 1
```

## Runtime numeric outcomes

### Int

Int addition, subtraction, multiplication, and unary negation fault when the mathematical result is outside the signed 64-bit range. Division truncates toward zero. Remainder has the sign of the dividend (or is zero), satisfying `a = (a / b) * b + a % b` mathematically. A zero divisor faults for both operations. Minimum Int divided by -1 faults, while Minimum Int modulo -1 is zero. Unary negation of Minimum Int faults. Thus `-7 / 2` is -3 and `-7 % 3` is -1.

### Float

Float operations round each operator result to binary64, nearest with ties to even; no implicit fused multiply-add or reassociation is permitted. Arithmetic overflow produces signed infinity; division by zero follows IEEE behavior, including infinity for nonzero/zero and NaN for zero/zero. Invalid Float arithmetic produces NaN, without a programming fault. Underflow rounds to a subnormal or signed zero. NaN makes every ordering comparison false; equality is false and inequality true, including against itself. Positive and negative zero compare equal. Native adapters may deliver these values. Source literals still reject a magnitude rounding to infinity. [String formatting](text-and-bytes.md#deterministic-formatting) specifies non-finite spellings.

### Decimal

Decimal is finite base-ten arithmetic with 34 significant digits. Its representable values are `c × 10^q`, with signed integer coefficient `c` of at most 34 digits and quantum exponent `q` between -6176 and 6111 inclusive. This gives a largest adjusted exponent of 6144, a smallest normal adjusted exponent of -6143, and subnormals down to `1e-6176d`. Decimal has no NaN or infinity; all zero encodings have the same numerical value and format as `0`.

For each Decimal operator:

1. Compute the exact mathematical result. Division by zero faults.
2. For a nonzero magnitude with adjusted decimal exponent `e`, choose quantum `q = max(e - 33, -6176)`.
3. Round the exact value divided by `10^q` to an integer coefficient, ties to even. If it has 35 digits, shift one exact trailing zero into `q`.
4. Require an equivalent representation with at most 34 coefficient digits and `q` in range. Otherwise overflow faults.

There is one rounding step per operator. Do not round intermediate coefficients, reassociate operators, or saturate to the maximum finite value. Underflow produces a subnormal or zero without fault. `1d / 3d` is `0.3333333333333333333333333333333333d`. Equality and ordering compare exact stored numerical values, ignoring scale and trailing zeroes.

Decimal literals are accepted only when their exact mathematical value is representable without rounding. Insignificant leading/trailing coefficient zeroes do not count against precision: `1.00d` is exact. A literal requiring 35 significant digits, such as `1.2345678901234567890123456789012345d`, or lying outside the representable grid is a compile error. `1e6144d` and `1e-6176d` are accepted; `1e6145d` and `1e-6177d` are rejected. Unary-negative literal checking follows the same magnitude rules. Runtime conversion and arithmetic are separate from source literal acceptance.

The following calculation stays in `Decimal` because each numeric literal has a `d` suffix:

```text
let price = 100d
let percent = 15d
let discounted = price * (1d - percent / 100d)
```

Use ordinary validation when invalid numbers are expected inputs. [Expected failures](../errors/results.md) shows how to return a domain error before calculating a discount; [programming faults](../errors/faults.md) explains invariant failures.

## Booleans

A Boolean value controls an [if statement](../control-flow/conditionals.md) or [while loop](../control-flow/loops.md). There is no numeric-to-Boolean conversion implied by using a number as a condition.

## Durations

`milliseconds`, `seconds`, and `minutes` are Int members: `500.milliseconds` and `2.seconds` have type `Duration`. They also work on nonliteral Int expressions; `Instant` represents a monotonic clock instant. They are used by [timeouts and deadlines](../../concurrency/cancellation.md).

[Previous: Destructuring bindings](destructuring.md) · [Next: String and bytes](text-and-bytes.md)
