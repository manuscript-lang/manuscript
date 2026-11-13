+++
title = "Strings and bytes"
weight = 4
+++

# Strings and bytes

`String` is immutable, always valid UTF-8, and needs no import. `Bytes` is immutable raw data; import it from `@std/bytes.ms` to name the type.

## String literals

A literal is delimited by `"` and fits on one source line, interpolations included. Raw newlines and control characters U+0000 to U+001F are rejected; other Unicode appears directly. [Raw and multi-line literals](#multi-line-and-raw-literals) skip escapes or span lines. There are no single-quoted or byte literals.

| Escape | Value |
| --- | --- |
| `\"` | Double quote |
| `\\` | Backslash |
| `\n` | LF, U+000A |
| `\r` | CR, U+000D |
| `\t` | Tab, U+0009 |
| `\{`, `\}` | Literal opening/closing brace; plain `{` opens an interpolation |
| `\u{H}` | Unicode scalar with one to six hexadecimal digits H |

Hex digits may be either case. Scalars above U+10FFFF, surrogates U+D800 to U+DFFF, unknown escapes, an unescaped closing brace, and unterminated literals are compile errors. `\u{0}` is a valid null character.

```manuscript
quote := "She said \"hello\"."
template := "Literal braces: \{name\}"
lines := "first\nsecond"
symbol := "\u{1F642}"
```

## Multi-line and raw literals

`"""` opens text that spans lines. The opening quotes end their line, the closing quotes stand alone on a later line, and the closing line's indentation is removed from every line, so the text can be indented with the code around it. The line break after the opening quotes and the one before the closing line are not part of the value. A blank line may be shorter than the indentation; any other line indented less than the closing quotes is an error. Escapes and `{expression}` interpolation work as in `"..."` (an interpolated expression still stays on one line), and `"` needs no escape. The text cannot contain `"""` at all.

`r"..."` is one-line raw text: every character is literal up to the first `"`, so there are no escapes and no interpolation, and it cannot contain a quote. Use it for regular expressions and Windows paths: `digits := r"\d+"`. Control characters (tabs included) are rejected as in `"..."`; use `r"""` for text with quotes.

`r"""` opens raw text with the same layout where every character is literal: no escapes, no interpolation, braces and backslashes included. Use it for JSON, regular expressions, and fixtures.

```manuscript
name := "Ada"
greeting := """
    Hello, {name}!
      Indented line, "quoted".
    """
config := r"""
    {"name": "ada", "tags": ["a", "b"], "pattern": "\d+"}
    """
```

`greeting` is `Hello, Ada!` and `  Indented line, "quoted".` on two lines; `config` holds the JSON exactly as written. Import paths, `test` names and `bench` names must be one-line `"..."` text. The formatter keeps the literal's lines and moves them with the line where the literal starts.

Strings are never normalized: `"é"` and `"e\u{301}"` are distinct values. [Equality](../types/equality-and-hashing.md) compares contents exactly.

## Interpolation

Every `"..."` literal interpolates: an unescaped `{` opens an embedded [expression](expressions.md) closed by its matching `}`, and there is no `f` prefix. Calls and nested literals are allowed. Empty expressions, format suffixes, comments, and newlines are rejected. Escape both braces for JSON-like text: `"\{\"a\": 1\}"`.

```manuscript
name := "Ada"
count := 3
greeting := "Welcome, {name}!"
calculated := "Next: {count + 1}"
```

Embedded expressions evaluate once, left to right, each formatted before the next. Propagation or a fault stops the rest. Every value is formattable using the same conversion as `to_string()`; interpolation adds no implicit conversions elsewhere.

## Converting values to String

Every value has a built-in `to_string() String`, needing no import or bound. A bound method keeps its receiver:

```manuscript
fn text[T](value: T) String:
    return value.to_string()

test "string conversion":
    count := 3
    convert: fn() String := count.to_string
    _direct := count.to_string()
    _bound := convert()
    _embedded := "{count}"
```

Each conversion produces `"3"`. Passing an Int to a String parameter still needs `.to_string()`.

The built-in method wins over any field or interface operation named `to_string` and cannot be overridden. Conversion never calls user-defined formatting or resource operations; a closed resource is still printable.

## Indexing and character boundaries

There is no `text[index]` or slice syntax: scalar position is not a constant-time offset in UTF-8, so use `get(index)` or `for c in text.chars()`. Each `get(index)` walks the text from the start, so a loop over indexes of long non-ASCII text is quadratic; `scalars(text)` from `@std/text.ms` is a stream that yields each scalar in constant time. Byte positions, scalars, and graphemes differ: `"é"` is two UTF-8 bytes; `"e\u{301}"` is two scalars and may display as one grapheme. Grapheme indexing is unsupported.

- `get`, `scalar_at`, `index_of`, `last_index_of`, `slice`, and `slice_scalars` use scalar indexes. `get(index, default:)` returns a one-scalar String; `scalar_at(index, default:)` its code point as an Int. Negative indexes count from the end; out of range gives the default, or a fault without one.
- Searches return the first or last scalar index or `none`. An empty search matches at 0 (`index_of`) or `scalar_length()` (`last_index_of`).
- `length()` and `scalar_length()` count scalars; `is_empty()` tests for zero.
- `chars()` returns a `List[String]` that borrows the receiver, like `split` and `lines`; `scalar_values()` returns code points.
- `reverse()` reverses scalars without normalization: `"e\u{301}".reverse()` is `"\u{301}e"`.
- `compare(other:)` returns `-1`, `0`, or `1` by scalar order, case-sensitive, a prefix first: `"Z".compare("a")` is `-1`; `"é".compare("e\u{301}")` is `1`.
- `lines()` splits at LF or CRLF, drops those terminators, keeps interior empty lines and lone CRs, and adds no item for a final newline: `"a\r\nb\n".lines()` is `["a", "b"]`, `"\n\n".lines()` is `["", ""]`, `"a\r".lines()` is `["a\r"]`.
- `split`, `lines` and `chars` lend their receiver: the result is used in place while the receiver stays unchanged, and keeping it (storing, returning, a `var` binding, an escaping closure) needs `.clone()`, as `Row(line.split(" ").clone())` does. A loop variable over a lent result borrows its piece, so `out.append(piece.clone())` keeps it.

### Half-open slices

All slice operations include `start` and exclude `end`. Let `n` be the receiver's scalar, element, or byte length:

| Operation | Bounds and result |
| --- | --- |
| `String.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return an `Error` of kind `"ERANGE"`. |
| `String.slice_scalars(start:, end:)` | Require `0 <= start <= end <= n` with no relative negative bounds; invalid bounds return an `Error` of kind `"ERANGE"`. |
| `List.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return an `Error` of kind `"ERANGE"`; success is a new owned List with independent storage. |
| `Bytes.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return an `Error` of kind `"ERANGE"`; success is an owned copy of the selected bytes. |

`String.view(start, end)` takes the same scalar bounds as `slice` and borrows the range without copying, like `Bytes.view`. A bound outside the string raises a fault, not an `Error`. The receiver must stay unchanged while the view is used; storing or returning a view is rejected, so call `.clone()` on it to keep an independent `String`. Use `slice` when you want an owned copy or an `ERANGE` error.

Equal bounds give an empty range. Bounds are never clamped or swapped; `text.slice(start: 0, end: n + 1)` is an `"ERANGE"` error, not a fault. `"aé🙂z".slice(start: -2, end: 4)` is `ok("🙂z")`; `slice(start: 3, end: 1)` and `slice(start: 1, end: 10)` are errors of kind `"ERANGE"`. See the [String](../../standard-library/reference/prelude.md#string), [collection](../../standard-library/reference/collections/collections.ms.md), and [Bytes](../../standard-library/reference/bytes.ms.md) references.

`Bytes.view(start, end)` uses the same byte bounds and borrows the range without copying. Invalid bounds raise a fault. The receiver must stay available while the view is used; call `.clone()` on the view to keep an independent value.

## Replacing text

`String.replace(old:, new:)` replaces every nonoverlapping literal occurrence, scanning left to right; inserted text is not searched again, so `"aaa".replace("aa", "b")` is `"ba"`. `String.replace_first(old:, new:)` replaces only the first occurrence. Both return a new String and leave the receiver unchanged. An empty `old` matches at each Unicode scalar boundary: `"ab".replace("", "-")` is `"-a-b-"` and `"ab".replace_first("", "-")` is `"-ab"`. Output beyond the string size limit is a programming fault, as for `concat`. Use `Regex.replace_all` for pattern matches or a bounded result.

For example, `"draft draft".replace("draft", "ready")` produces `"ready ready"`, while `replace_first` produces `"ready draft"`.

## Encoding and parsing

| Receiver or constructor | Signature/result |
| --- | --- |
| `String` | `byte_length() Int`; `to_bytes() Bytes`; `parse_int() Int?`; `parse_float() Float?` |
| `Bytes(values: List[UInt8])` | Immutable bytes; `Bytes([104, 105])` types its literals as `UInt8`, so a value outside 0–255 is a compile error |
| `Bytes` | `length() Int`; `get(index: Int, default: UInt8?) UInt8`; `[index] UInt8`; `concat(other: Bytes) Bytes` |
| `Bytes` | `decode_utf8() String?`; `decode_utf8_range(start: Int, end: Int) String?` |
| `Bytes` | `values() List[UInt8]`; a fresh mutable list of the bytes, one byte per element |

`to_bytes` encodes UTF-8. `Bytes.decode_utf8` succeeds exactly for valid UTF-8 and returns `none` otherwise. Byte `get(index, default:)` and `data[index]` return the byte as `UInt8`; convert with `to_int()` for arithmetic; negative indexes count from the end, and `[]` faults out of range where `get` takes a default. Bytes are immutable, so `data[i] = v` is rejected.

`Bytes(values:)` copies its list, and `data.values()` (like the free function `values(data:)` in `@std/bytes.ms`) returns a fresh copy; editing either never changes the Bytes. `values` is a method, not a data field.

`parse_int` accepts an optional ASCII `+` or `-` then one or more ASCII digits, in range. Leading zeros are fine; whitespace, separators, fractions, exponents, and trailing characters give `none`. `parse_float` takes an optional sign, digits, an optional fraction with digits on both sides of the point, an optional exponent, or `NaN`, `Infinity` and `-Infinity`; anything else, or a finite-looking value beyond the Float range, gives `none`. Use `math.parse_float` and `math.parse_int(text, radix)` when the failure cause or a radix is needed. Exact signatures are in the [API reference](../../standard-library/reference/_index.md). Grapheme and locale operations are unsupported.

`trim`, `trim_start` and `trim_end` remove the Unicode `White_Space` scalars: U+0009 to U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. Zero-width spaces (U+200B), U+180E and U+FEFF are not whitespace.

```manuscript
import panic from "@std/core.ms"

import Bytes from "@std/bytes.ms"

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic("check failed")
    if not ("é".to_bytes().decode_utf8() == "é"):
        return panic("check failed")
    invalid: String? := none
    if not (Bytes([255]).decode_utf8() == invalid):
        return panic("check failed")
    if not ("-007".parse_int() == -7):
        return panic("check failed")
```

## Padding and fixed digits

`pad_start(target_length, padding)` and `pad_end` return a `String`. The text grows to `target_length` scalars by repeating `padding` (the last copy is cut to fit); a shorter or negative target or empty padding returns the text unchanged. An output beyond the string limit faults, as `concat` does, so a table row needs no unwrapping. `Float.to_fixed(digits)`, `to_precision(precision)` and `to_exponential(digits)` also return a `String`; a count outside their range (0 to 100, or 1 to 100 for `to_precision`) is a programming fault.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn row(name: String, amount: Float) String:
    return name.pad_end(8, " ") + amount.to_fixed(2).pad_start(8, " ")

test "padding and fixed digits":
    expect_equal(row("total", 3.14159), "total       3.14")?
```

## Binary data

`Bytes` reads fixed-width numbers at an absolute offset: `int8`, `uint8`, and for each of `int16`, `int32`, `int64`, `uint16`, `uint32`, `float32`, `float64` a `_le` and `_be` spelling, such as `data.int32_le(at: 2)`. Each returns `T!` (`Result[T, Error]`); bytes that are not all there give an `Error` of kind `"ERANGE"`. Signed reads return `Int8`, `Int16`, `Int32` and `Int` (64-bit); `uint8`, `uint16` and `uint32` reads return `UInt8`, `UInt16` and `UInt32`; `float32` returns `Float32` and `float64` returns `Float`. `BytesBuilder` writes with matching `append_int32_le(value)` and siblings; `append` adds one byte and `append_bytes` adds many.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import BytesBuilder from "@std/bytes.ms"
import expect_equal from "@std/test/test.ms"

test "binary codecs":
    var out = BytesBuilder()
    out.append_uint16_be(258)
    out.append_float64_le(1.5)
    data := out.build()
    expect_equal(data.uint16_be(0)?, 258)?
    expect_equal(data.float64_le(2)?, 1.5)?
```

## Deterministic formatting

Interpolation and direct `to_string()` conversion use the forms below, independent of locale or host settings. To retain a type-specific representation with `print`, pass the converted text: `print("{value}")`. Generic `print(value)` can render types structurally.

| Type | Formatting |
| --- | --- |
| String | Contents unchanged; inserted braces/quotes are ordinary output characters and are not parsed again |
| Bool | `true` or `false` |
| Unit | `unit` |
| Int | Base-ten digits, optional leading minus, no separators or leading zeros |
| Float | Shortest round-trip decimal under the rule below; signed zero retains its sign |
| Decimal | Exact numerical decimal value, normalized as below; no significance/scale padding |
| Type | `Type(field: value, ...)`, with fields sorted by name and values recursively converted |
| Alternative | `Type.Case` for a nullary case; `Type.Case(value, ...)` for payloads in declaration order |
| Optional | `some(value)` or `none`; for example, an `Int?` holding 42 formats as `some(42)` |
| Result | `ok(value)` or `error(cause)`; for example, `ok(42)` formats as `ok(42)` |
| List | `[value, ...]` in element order |
| Map | `Map(key: value, ...)` in insertion order |
| Set | `Set(value, ...)` in insertion order |
| Bytes | `Bytes(byte, ...)`, with each byte in base ten; no UTF-8 decoding |
| Interface view | Conversion of its underlying receiver |
| Function | `[function]`, including bound methods; the function is not called |
| Duration | Human-readable units, such as `2s`, `250ms`, or `0s` |
| Instant | A type displaying its clock `domain` and nanosecond `tick` |
| BigInt | Base-ten integer digits |
| Timestamp | UTC RFC 3339 text with fractional seconds as needed |
| Regex | Pattern text |
| Other opaque native values, authorities, and resources | `[object]`; internal state and addresses are not inspected |

Type and enum names omit modules and type arguments. Nested Strings are unquoted. Empty values keep their delimiters: `[]`, `Map()`, `Type()`. These forms are for display, not serialization. At nesting depth 64 conversion emits `...`; the outer value is depth 0, and each field, payload, item, key/value, or interface receiver adds one.

**Float.** Choose the shortest decimal that converts back to the same binary64 (nearest, ties to even); among equal lengths take the closest to the exact value, then the even final digit. Strip trailing zeros. Zero is `0`, negative zero `-0`.

**Decimal.** Use the exact value, strip trailing zeros, and apply the same placement rule. Any zero is `0`; `1.00d` formats as `1`. For fixed places use [`to_fixed`](numbers-and-booleans.md#scale-rounding-and-fixed-places): `25.50d.to_fixed(digits: 2)` is `ok("25.50")`.

**Placement.** With `e` the base-ten exponent of the first nonzero digit, use plain notation when -6 ≤ e ≤ 20. Otherwise write one digit, then any remaining digits after a point, then `e`, an explicit sign, and the exponent without leading zeros: `0.000001` is plain, `1e-7` and `1e+21` are not.

Non-finite Floats format as `NaN`, `Infinity`, or `-Infinity` (see [numeric rules](numbers-and-booleans.md#runtime-numeric-outcomes)); they have no literal spelling.
