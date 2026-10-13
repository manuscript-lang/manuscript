+++
title = "Strings and bytes"
weight = 4
+++

# Strings and bytes

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

An unescaped `{` opens an embedded expression, and its matching `}` closes it. Interpolation uses the ordinary [expression grammar](expressions.md), including calls and nested text literals. The scanner balances expression delimiters and recognizes text escapes/nested text literals; braces inside a nested literal do not terminate the enclosing expression. Empty expressions, interpolation format suffixes, comments within the embedded expression, and physical newlines inside an interpolated literal are rejected. A function expression with a statement suite consequently cannot appear inside interpolation. JSON, code snippets, and other text containing braces must escape both braces (`"\{\"a\": 1\}"`); a failure inside an interpolation reminds the writer of the escape.

```manuscript
let name = "Ada"
let count = 3
let greeting = "Welcome, {name}!"
let calculated = "Next: {count + 1}"
```

Embedded expressions evaluate once each from left to right. Each result is formatted before evaluating the next embedded expression. Plain surrounding text is concatenated with those formatted results. Result propagation or a fault stops evaluation of the remainder. Interpolation formats values; it does not permit implicit conversions at call, assignment, or return boundaries.

Every value is directly formattable, including records, alternatives, collections, functions, Bytes, interface views, runtime resources, and unconstrained type parameters. Interpolation uses the same conversion as `toString()`.

## Converting values to String

Every value has a built-in `toString()` method with signature `fn() -> String`. It needs no import or generic bound. A bound method retains its receiver and can be called later:

```manuscript
fn text[T](value: T) -> String:
    return value.toString()

test "string conversion":
    let count = 3
    let convert: fn() -> String = count.toString
    let direct = count.toString()
    let bound = convert()
    let embedded = "{count}"
```

Each conversion above produces `"3"`. Every value supports explicit text conversion; the exact representations are defined below. Assignment, arguments, and return values still require compatible types: passing an Int to a String parameter requires an explicit `.toString()`.

The built-in method takes precedence over a field or interface operation named `toString`. It cannot be overridden. Application-specific display functions can return String explicitly. Conversion never invokes user-defined formatting operations or native resource operations; even a closed resource remains printable.

## Indexing and character boundaries

There is no `text[index]` or slicing syntax. String `at`, `scalar_at`, `index_of`, `last_index_of`, `slice`, and `slice_scalars` use Unicode scalar indexes, not byte offsets. `at` returns a one-scalar String; `scalar_at` returns its integer code point. Both accept negative indexes relative to the end and return `none` out of range. Search returns the first or last matching scalar index, or `none`; an empty search matches at zero for `index_of` and at `scalar_length()` for `last_index_of`.

A byte position, a Unicode scalar, and a user-visible grapheme are different units. For example, `"é"` has two UTF-8 bytes; `"e\u{301}"` has two scalars but can display as one grapheme. Byte lookup alone cannot select a character.

`length()` and `scalar_length()` count scalars; `is_empty()` reports whether that count is zero. `chars()` returns a fresh `List[String]` with one scalar per item, while `scalar_values()` returns their integer code points in order. `reverse()` reverses scalar order without normalization: `"e\u{301}".reverse()` is `"\u{301}e"`, so combining sequences and graphemes may change. Bytes use byte indexes and Lists use element indexes. Grapheme indexing is unsupported.

`compare(other:)` returns exactly `-1`, `0`, or `1` in lexical Unicode scalar order. It compares case-sensitive contents without locale rules or normalization; a proper prefix sorts before the longer text. For example, `"Z".compare("a")` is `-1`, while `"é".compare("e\u{301}")` is `1`.

`lines()` returns a fresh `List[String]`, splitting at LF or CRLF and removing those terminators. It preserves interior empty lines and every CR not immediately before LF. A terminal newline does not create an extra item, and empty text returns an empty list: `"a\r\nb\n".lines()` is `["a", "b"]`, `"\n\n".lines()` is `["", ""]`, and `"a\r".lines()` is `["a\r"]`. Other Unicode line separators remain ordinary contents. Both `lines()` and `chars()` leave the String unchanged and return independent mutable list storage on every call, including empty calls.

### Half-open slices

All slice operations include `start` and exclude `end`. Let `n` be the receiver's scalar, element, or byte length:

| Operation | Bounds and result |
| --- | --- |
| `String.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `StringError.OutOfRange`. |
| `String.slice_scalars(start:, end:)` | Require `0 <= start <= end <= n` with no relative negative bounds; invalid bounds return `StringError.OutOfRange`. |
| `List.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `CollectionError.OutOfRange`; success is a new shallow List with independent outer storage. |
| `Bytes.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `CollectionError.OutOfRange`; success is immutable Bytes that may share immutable storage. |

Equal valid bounds select an empty range. Slices never clamp or swap bounds, so an off-by-one such as `text.slice(start: 0, end: n + 1)` is an expected `OutOfRange` error rather than a shorter result or a fault. Negative bounds are relative to the end, as for `at`. String slices preserve scalar boundaries and leave their receiver unchanged. For example, `"aé🙂z".slice(start: -2, end: 4)` is `ok("🙂z")`, while `"aé🙂z".slice(start: 3, end: 1)` and `"aé🙂z".slice(start: 1, end: 10)` are `error(StringError.OutOfRange)`. Unwrap only when the bounds are known to be valid. Exact signatures appear in the [String reference](../../standard-library/reference/prelude.md#string), [collection reference](../../standard-library/reference/collections.md), and [Bytes reference](../../standard-library/reference/bytes.md).

## Encoding and parsing

| Receiver or constructor | Signature/result |
| --- | --- |
| `String` | `byte_length() -> Int`; `to_bytes() -> Bytes`; `parse_int() -> Optional[Int]` |
| `Bytes(values: List[Int])` | Immutable bytes; each value must be 0–255, otherwise a programming fault |
| `Bytes` | `length() -> Int`; `at(index: Int) -> Optional[Int]`; `concat(values: Bytes) -> Bytes` |
| `Bytes` | `to_text() -> Optional[String]` |
| `Bytes` | `values() -> List[Int]`; a fresh mutable list of unsigned byte values |

`String.to_bytes` uses UTF-8. `Bytes.to_text` succeeds exactly for valid UTF-8, preserving contents without normalization; invalid bytes produce `none`. Byte `at` follows list index behavior and returns the unsigned byte as Int. An empty `Bytes(values: [])` is valid.

`Bytes(values:)` copies the supplied list; subsequent list mutation does not change the Bytes. `data.values()` returns a fresh list, so editing that result does not change `data`. The existing free function `values(data:)` from `@std/bytes.ms` returns the same kind of copy. `values` is a receiver operation, not a readable data field; the constructor's `values:` argument remains a List.

`parse_int` accepts exactly an optional ASCII `+` or `-` followed by one or more ASCII decimal digits and an in-range mathematical value. It permits leading zeros, rejects whitespace, separators, fractions, exponents, and any unconsumed character, and returns `none` for invalid or out-of-range input. Runtime parsing is distinct from the stricter source literal grammar. See [text and collection operations](../../standard-library/data.md) and [numeric operations](../../standard-library/math.md) for more methods; exact signatures live in the [API reference](../../standard-library/reference/_index.md). Grapheme and locale operations remain unsupported.

```manuscript
import panic from "@std/faults.ms"

import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic(message: "check failed")
    if not ("é".to_bytes().to_text() == some("é")):
        return panic(message: "check failed")
    let invalid: Optional[String] = none
    if not (Bytes([255]).to_text() == invalid):
        return panic(message: "check failed")
    if not ("-007".parse_int() == some(-7)):
        return panic(message: "check failed")
```

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
| Record | `Type(field: value, ...)`, with fields sorted by name and values recursively converted |
| Alternative | `Type.Case` for a nullary case; `Type.Case(value, ...)` for payloads in declaration order |
| Optional | `Optional.some(value)` or `Optional.none`; for example, `some(42)` formats as `Optional.some(42)` |
| Result | `Result.ok(value)` or `Result.error(cause)`; for example, `ok(42)` formats as `Result.ok(42)` |
| List | `[value, ...]` in element order |
| Map | `Map(key: value, ...)` in insertion order |
| Set | `Set(value, ...)` in insertion order |
| Bytes | `Bytes(byte, ...)`, with each byte in base ten; no UTF-8 decoding |
| Interface view | Conversion of its underlying receiver |
| Function | `[function]`, including bound methods; the function is not called |
| Duration | Signed nanoseconds followed by `ns`, such as `2000000ns` |
| Instant | `Instant(tick)`, with its nanosecond tick in base ten |
| OperationId | `OperationId(number)`, with its number in base ten |
| BigInt | Base-ten integer digits |
| Timestamp | UTC RFC 3339 text with fractional seconds as needed |
| Regex | Pattern text |
| Other opaque native values, authorities, and resources | `[object]`; internal state and addresses are not inspected |

Type names in records and alternatives omit module identities and type arguments. Nested Strings retain their contents without quoting. Empty values use the same delimiters with no items, such as `[]`, `Map()`, and `Type()`. These text forms are for display; they are not a serialization or identity format. At nesting depth 64, conversion emits `...` for that value, so deeply nested or cyclic adapter values terminate. The outer value starts at depth zero; entering a field, payload, collection item, map key/value, or interface receiver adds one.

For a finite nonzero Float, choose the decimal significand with the fewest significant digits whose numerical conversion to binary64 under round-to-nearest, ties-to-even yields the original value. If several candidates have that digit count, choose the one numerically closest to the exact binary value; if equally close, choose the candidate with an even final significand digit. Remove trailing significand zeros and place the decimal point under the rendering rule below. A zero formats as `0`; negative zero formats as `-0`.

For Decimal, use the exact stored numerical value rather than an intermediate Float conversion. Remove trailing fractional/significand zeros without changing the number, and use the same decimal-point rule. Any Decimal zero formats as `0`. Formatting does not round a Decimal to a smaller precision or preserve its source spelling: `1.00d` formats as `1`.

For a chosen number of fractional digits, use Decimal's [scale rounding and fixed-place formatting](numbers-and-booleans.md#scale-rounding-and-fixed-places). `25.50d.to_fixed(digits: 2)` returns `ok("25.50")`; interpolation and `toString()` retain the normalized representation above.

For either finite numerical decimal, let e be the base-ten exponent of its first nonzero digit in scientific notation. Use plain decimal notation when -6 ≤ e ≤ 20, adding zeros as necessary. Otherwise use one digit before the decimal point, remaining significant digits after it (omit the point if there are none), followed by lowercase `e`, an explicit `+` or `-`, and the exponent magnitude without leading zeros. For example, `0.000001` uses plain notation and an exponent of -7 uses `1e-7`; an exponent of 21 uses `1e+21`.

Non-finite Float values format as `NaN`, `Infinity`, or `-Infinity`; NaN payloads and signs do not affect that text. The [numeric rules](numbers-and-booleans.md#runtime-numeric-outcomes) define how these values arise; they have no source literal spelling.

## External data

[Capability adapters](../../contributing/compiler/adapters/_index.md) validate UTF-8 when constructing text from foreign values and preserve immutability when transferring buffers. See [standard imports](../../standard-library/imports.md) for the names available without imports.
