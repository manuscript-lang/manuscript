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
| `Int` | Signed 32-bit integer with checked arithmetic |
| `Float` | IEEE 754 binary32 |
| `Int64` | Explicit signed 64-bit integer with checked arithmetic |
| `Float64` | Explicit IEEE 754 binary64 |
| `Decimal` | Base-10, 34 significant digits, round half to even |
| `Bool` | `true` or `false` |

## Arithmetic and conversion

Numeric conversions are explicit. Int/Int64 overflow and invalid integer/Decimal operations produce programming faults; Float/Float64 operations follow the non-finite rules below. An inferred local type does not authorize an implicit conversion at a call boundary. The [numeric conversion rules](#numeric-conversion) below define the callable conversions.

Arithmetic operands must have the same exact numeric type, and the result has that type. Unary signs retain their operand type. `%` accepts matching `Int` or matching `Int64` operands. Ordering comparisons accept matching numeric types and return `Bool`; equality additionally follows the [Equal rules](../types/equality-and-hashing.md). The [expression table](expressions.md#operand-and-result-types) is authoritative for operator typing.

Default integer literals are checked against the signed 32-bit range at compile time, from `-2147483648` to `2147483647`. The magnitude `2147483648` is accepted only as a directly negated integer literal, giving `-2147483648`; parentheses immediately around that literal do not change the check. The positive literal and magnitudes outside either signed boundary are rejected. A Float literal rounds to binary32 using nearest, ties to even; one whose rounded magnitude would be infinite is rejected. An explicit `Int64` or `Float64` context selects that literal type before checking its range or rounding its value. Int64 literals span `-9223372036854775808` to `9223372036854775807`, with the same directly negated minimum rule; Float64 literals round to finite binary64. The ordinary Int/Float categories remain distinct: an integer-shaped token does not become Float64 from context. Typed values still require explicit conversion.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Decimal from "@std/decimal.ms"
import panic from "@std/faults.ms"
test "literal widths":
    let smallest: Int = -2147483648
    let wide_smallest: Int64 = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    if smallest % -1 != 0 or wide_smallest % -1 != 0:
        return panic("minimum remainder")
    if exponent != 1000.0 or precise != 1000d:
        return panic("literal category")
```

An integer-shaped token does not become Float from context: `let mismatch: Float = 1` is rejected.

## Explicit wider values

Use `Int64` for integer contracts that require a wide range, and `Float64` when a contract requires binary64 precision. The defaults use four-byte scalar payloads; Int64 and Float64 use eight. Generic values and record fields are boxed, so object headers, interface slots and alignment still contribute to memory usage. This is a breaking default-width change: formerly accepted large unconstrained literals require a wide annotation, and Float calculations have binary32 precision.

An annotation, parameter, field, default, return, collection element, callback result or match result can provide a concrete wider context for a literal. Literal-only arithmetic can use that result context. A known wide operand also provides context to a numeric literal on the other side. The checker selects the width before parsing or rounding; it never rounds a literal to the default Float and then widens it.

```manuscript
let counter: Int64 = 3000000000
let precise: Float64 = 0.10000000000000001
let advanced = counter + 1
```

An unconstrained literal keeps its default category. Already typed names, fields, call results and generic payloads keep their type. Thus `let small = 1; let wide: Int64 = 1` does not permit `small + wide`: use `small.to_int64() + wide`. Generic numeric arguments use a concrete parameter or explicit result context when available, and otherwise contribute their default type. Ordinary Optional assignment/return rules do not change; a plain literal supplied to an `Optional[Int64]` parameter uses the payload context and the existing argument wrapper.

There is no new literal suffix or built-in constructor. `parse_int64(text, radix)` and `parse_float64(text)` in `@std/numbers.ms` parse directly into the wider types, without a default-width intermediate. The integer parser distinguishes invalid radix/text and out-of-range values; the float parser retains NaN, signed infinities and signed zero under the existing numeric text grammar.

## Numeric conversion

| Receiver | Signature/result |
| --- | --- |
| `Int` | `to_int64() -> Int64`; `to_float() -> Float`; `to_float64() -> Float64`; `to_decimal() -> Decimal` |
| `Float` | `to_float64() -> Float64`; `truncate_to_int() -> Optional[Int]`; `truncate_to_int64() -> Optional[Int64]` |
| `Decimal` | `to_float() -> Float`; `to_float64() -> Float64`; `truncate_to_int() -> Optional[Int]`; `truncate_to_int64() -> Optional[Int64]` |
| `Int64` | `to_int() -> Optional[Int]`; `to_float() -> Float`; `to_float64() -> Float64`; `to_decimal() -> Decimal` |
| `Float64` | `to_float() -> Float`; `truncate_to_int() -> Optional[Int]`; `truncate_to_int64() -> Optional[Int64]` |

Int→Decimal is exact. Int→Float and Decimal→Float round once directly to nearest binary32, ties to even. Decimal→Float may produce signed infinity or signed zero under the Float rules. Truncation discards the fractional part toward zero, then checks the mathematical integer against the destination signed limits before conversion. NaN, infinities, or an out-of-range integer yield `none`.

For example, `1e30.truncate_to_int()` is `none`. Float +2^31 cannot convert to Int, while Float -2^31 converts to its minimum. Float64 +2^63 cannot truncate to Int64, while Float64 -2^63 converts to its minimum.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"
test "conversion boundaries":
    if 1e30.truncate_to_int().is_some(): return panic("default range")
    if 2147483648.0.truncate_to_int().is_some(): return panic("positive limit")
    if (-2147483648.0).truncate_to_int().unwrap() != -2147483648:
        return panic("default minimum")
    let too_large: Float64 = 1e300
    let wide_minimum: Float64 = -9223372036854775808.0
    if too_large.truncate_to_int64().is_some(): return panic("wide range")
    if wide_minimum.truncate_to_int64().unwrap() != -9223372036854775808:
        return panic("wide minimum")
```

Int64→Int checks the complete mathematical value against Int's range and returns `none` if it does not fit. Float64 truncation discards the fractional part before checking the destination range and host cast, including the exactly representable +2^63 boundary. Int64→Float rounds directly to binary32 without a binary64 intermediate. Integer-to-Float64 rounds directly to binary64; integer-to-Decimal is exact. Float64 formatting/classification supports the same `to_string`, `to_precision`, `to_exponential`, `to_fixed`, `is_nan` and `is_finite` operations as Float. Float64 remains non-Hashable, while Int64 equality and hashing retain exact integer value semantics at generic/collection boundaries.

## Runtime numeric outcomes

### Int

Int addition, subtraction, multiplication, and unary negation fault when the mathematical result is outside the signed 32-bit range. Division truncates toward zero. Remainder has the sign of the dividend (or is zero), satisfying `a = (a / b) * b + a % b` mathematically. A zero divisor faults for both operations. Minimum Int divided by -1 faults, while Minimum Int modulo -1 is zero. Unary negation of Minimum Int faults. Thus `-7 / 2` is -3 and `-7 % 3` is -1.

Int `/` and `%` faults name the operator and the invalid right operand. Division overflow also gives both operands and the signed 64-bit result range. These remain programming faults, while BigInt division returns its declared Result error.

### Float

Float operations round each operator result to binary32, nearest with ties to even; no implicit fused multiply-add or reassociation is permitted. Arithmetic overflow produces signed infinity; division by zero follows IEEE behavior, including infinity for nonzero/zero and NaN for zero/zero. Invalid Float arithmetic produces NaN, without a programming fault. Underflow rounds to a subnormal or signed zero. NaN makes every ordering comparison false; equality is false and inequality true, including against itself. Positive and negative zero compare equal. Native adapters may deliver these values. Source literals still reject a magnitude rounding to infinity. [String formatting](text-and-bytes.md#deterministic-formatting) specifies non-finite spellings.

Float64 uses the same IEEE outcomes and comparisons, with each operator result rounded to binary64 instead. Int64 uses the same checked integer outcomes over the signed 64-bit range. Neither type changes the width of an already typed operand.

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
    match amount_text():
        ok(text):
            if text != "tax 4.95 total 64.92 padded 25.50":
                return panic("unexpected amount text")
        error(cause):
            return panic(cause.message())
```

## Booleans

A Boolean value controls an [if statement](../control-flow/conditionals.md) or [while loop](../control-flow/loops.md). There is no numeric-to-Boolean conversion implied by using a number as a condition.

## Durations

`milliseconds`, `seconds`, and `minutes` are Int and Int64 members: `500.milliseconds` and `2.seconds` have type `Duration`. They also work on nonliteral Int expressions; `Instant` represents a monotonic clock instant. They are used by [timeouts and deadlines](../../concurrency/cancellation.md).

`Duration` is a signed 64-bit count of nanoseconds. The three unit members work on any Int or Int64 expression and multiply by 1,000,000, 1,000,000,000, or 60,000,000,000 with overflow checks. Import `duration` from `@std/time.ms` to construct an exact interval from nanoseconds. Integer unit conversions return Int64 and truncate toward zero; floating conversions return Float64 with binary64 rounding. `duration` takes Int64 nanoseconds, and Duration scaling/division take explicit Int64 operands. Timestamp Unix seconds and construction also retain Int64; its nanosecond component fits Int. `Instant` is an opaque monotonic instant in the current run's clock domain; it has no source constructor. Clock adapters and injected test clocks must preserve a single comparable domain within a run. Cross-domain comparison or subtraction faults. Duration arithmetic and Instant shifts/differences check overflow; these compiler-defined operations are enumerated in the [operator table](expressions.md).

Duration and Instant overflow diagnostics name the arithmetic operation, the operands in nanoseconds, and the signed 64-bit result range; multiplication factors and divisors remain dimensionless. Duration `divide` names an invalid divisor. Unit-member conversion and Duration `negate`/`abs` faults give the allowed input range and original value. The arithmetic, rounding, clock-domain, and cancellation rules remain unchanged.

`2.seconds` is 2,000,000,000 nanoseconds. Unsupported unit names and mixed arithmetic such as `2.seconds + 1` are type errors.

See [time value methods](../../standard-library/system.md#time-value-methods) for Duration, Instant, and Timestamp operations.
