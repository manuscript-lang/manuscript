+++
title = "Strings and bytes"
weight = 10
+++

# Strings and bytes

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `String` for text and `Bytes` for raw data. Both are immutable. Strings always contain valid UTF-8 and are available without an import. Import `Bytes` from `@std/bytes.ms` when naming that type. A byte sequence may need decoding before it can be treated as text.

## String literals

A text literal starts and ends with `"` and occupies one physical source line, including its interpolation expressions. Raw newlines and raw control characters U+0000 through U+001F are rejected. Other Unicode scalar characters can appear directly. A literal evaluates to String; there are no single-quoted, raw, multiline, or byte literals.

| Escape | Value |
| --- | --- |
| `\"` | Double quote |
| `\\` | Backslash |
| `\n` | LF, U+000A |
| `\r` | CR, U+000D |
| `\t` | Tab, U+0009 |
| `\{`, `\}` | Literal opening/closing brace |
| `\u{H}` | Unicode scalar with one to six hexadecimal digits H |

Scalar escapes accept uppercase or lowercase hexadecimal digits. Values above U+10FFFF and surrogates U+D800 through U+DFFF are compile errors. Unknown escapes, an unescaped closing brace, and an unterminated literal are compile errors. A brace inside a scalar escape belongs to that escape, not to interpolation. Null can be written as `\u{0}`; it remains valid String and is not a string terminator.

```manuscript
let quote = "She said \"hello\"."
let template = "Literal braces: \{name\}"
let lines = "first\nsecond"
let symbol = "\u{1F642}"
```

These are function-body fragments. String is stored and compared without implicit Unicode normalization. The single scalar `"é"` and the two-scalar `"e\u{301}"` remain distinct values even when they render similarly. UTF-8 encoding uniquely represents their scalar sequences; [String equality](../types/equality-and-hashing.md) compares those contents exactly.

## Interpolation

An unescaped `{` opens an embedded expression, and its matching `}` closes it. Interpolation uses the ordinary [expression grammar](expressions.md), including calls and nested text literals. The scanner balances expression delimiters and recognizes text escapes/nested text literals; braces inside a nested literal do not terminate the enclosing expression. Empty expressions, interpolation format suffixes, comments within the embedded expression, and physical newlines inside an interpolated literal are rejected. A function expression with a statement suite consequently cannot appear inside interpolation.

```manuscript
let name = "Ada"
let count = 3
let greeting = "Welcome, {name}!"
let calculated = "Next: {count + 1}"
```

Embedded expressions evaluate once each from left to right. Each result is formatted before evaluating the next embedded expression. Plain surrounding text is concatenated with those formatted results. Result propagation or a fault stops evaluation of the remainder. Interpolation formats values; it does not permit implicit conversions at call, assignment, or return boundaries.

Only String, Bool, Unit, Int, Float, and Decimal are directly formattable. An interpolation of a record, alternative, collection, function, Bytes, or runtime authority/resource type is a type error. Generic code needs a concrete supported scalar type; Equal, Hashable, or a matching operation name alone does not grant formatting eligibility. Custom data must call an explicit operation returning String, and then interpolate that String. No custom formatting protocol or user-defined operator is implied.

## Deterministic formatting

Formatting never depends on locale, host display settings, or a process's decimal separator.

| Type | Formatting |
| --- | --- |
| String | Contents unchanged; inserted braces/quotes are ordinary output characters and are not parsed again |
| Bool | `true` or `false` |
| Unit | `unit` |
| Int | Base-ten digits, optional leading minus, no separators or leading zeros |
| Float | Shortest round-trip decimal under the rule below; signed zero retains its sign |
| Decimal | Exact numerical decimal value, normalized as below; no significance/scale padding |

For a finite nonzero Float, choose the decimal significand with the fewest significant digits whose numerical conversion to binary64 under round-to-nearest, ties-to-even yields the original value. If several candidates have that digit count, choose the one numerically closest to the exact binary value; if equally close, choose the candidate with an even final significand digit. Remove trailing significand zeros and place the decimal point under the rendering rule below. A zero formats as `0`; negative zero formats as `-0`.

For Decimal, use the exact stored numerical value rather than an intermediate Float conversion. Remove trailing fractional/significand zeros without changing the number, and use the same decimal-point rule. Any Decimal zero formats as `0`. Formatting does not round a Decimal to a smaller precision or preserve its source spelling: `1.00d` formats as `1`.

For either finite numerical decimal, let e be the base-ten exponent of its first nonzero digit in scientific notation. Use plain decimal notation when -6 ≤ e ≤ 20, adding zeros as necessary. Otherwise use one digit before the decimal point, remaining significant digits after it (omit the point if there are none), followed by lowercase `e`, an explicit `+` or `-`, and the exponent magnitude without leading zeros. For example, `0.000001` uses plain notation and an exponent of -7 uses `1e-7`; an exponent of 21 uses `1e+21`.

Non-finite Float values format as `NaN`, `Infinity`, or `-Infinity`; NaN payloads and signs do not affect that text. The [numeric rules](numbers-and-booleans.md#runtime-numeric-outcomes) define how these values arise; they have no source literal spelling.

## Indexing and character boundaries

There is no `text[index]` or slicing syntax. The [data API](../../standard-library/data-and-io/operations.md#strings-and-bytes) defines byte length, UTF-8 encoding/decoding, and byte lookup. Scalar and grapheme indexing are unsupported.

A byte position, a Unicode scalar, and a user-visible grapheme are different units. For example, `"é"` has two UTF-8 bytes; `"e\u{301}"` has two scalars but can display as one grapheme. Byte lookup alone cannot select a character.

## External data

[Capability adapters](../../modules-and-capabilities/adapters/_index.md) validate UTF-8 when constructing text from foreign values and preserve immutability when transferring buffers. The [standard type catalog](../../standard-library/types/catalog.md) lists both types alongside the intrinsic and imported standard types.

[Previous: Numbers and booleans](numbers-and-booleans.md) · [Next: Records and nominal types](../types/records.md)
