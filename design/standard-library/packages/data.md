+++
title = "Text, bytes, and collections"
weight = 49
+++

# Text, bytes, and collections

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use these modules for text transformations, raw bytes, encodings, collection algorithms, and regular expressions. Import the functions you need from the module above each signature block. Read the behavior sections for indexing, ordering, and limit rules.

## `@std/string.ms`

```manuscript
fn contains(value: String, text: String) -> Bool
fn ends_with(value: String, suffix: String) -> Bool
fn from_scalars(values: List[Int]) -> Result[String, TextError]
fn join(parts: List[String], separator: String) -> String
fn lower(text: String) -> String
fn repeat(text: String, count: Int, max_bytes: Int) -> Result[String, TextError]
fn replace(text: String, old: String, new: String, max_replacements: Int) -> String
fn scalar_length(text: String) -> Int
fn scalar_values(text: String) -> List[Int]
fn slice_scalars(text: String, start: Int, end: Int) -> Result[String, TextError]
fn split(text: String, separator: String, max_parts: Int) -> List[String]
fn starts_with(value: String, prefix: String) -> Bool
fn trim(text: String) -> String
fn upper(text: String) -> String
```

## `@std/bytes.ms`

```manuscript
fn contains(data: Bytes, value: Bytes) -> Bool
fn slice(data: Bytes, start: Int, end: Int) -> Bytes
fn values(data: Bytes) -> List[Int]
```

## `@std/encoding.ms`

```manuscript
fn base64_decode(text: String, url_safe: Bool, max_bytes: Int) -> Result[Bytes, EncodingError]
fn base64_encode(data: Bytes, url_safe: Bool) -> String
fn hex_decode(text: String, max_bytes: Int) -> Result[Bytes, EncodingError]
fn hex_encode(data: Bytes) -> String
```

## `@std/binary.ms`

```manuscript
fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, BinaryError]
fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int, BinaryError]
fn write_float(value: Float, little_endian: Bool) -> Bytes
fn write_integer(value: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, BinaryError]
```

## `@std/collections.ms`

```manuscript
fn difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
fn filter[T](values: List[T], predicate: fn(value: T) -> Bool) -> List[T]
fn fold[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A
fn intersection[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
fn map[T, U](values: List[T], transform: fn(value: T) -> U) -> List[U]
fn map_keys[K: Hashable, V](values: Map[K, V]) -> List[K]
fn map_values[K: Hashable, V](values: Map[K, V]) -> List[V]
fn reverse[T](values: List[T]) -> List[T]
fn slice[T](values: List[T], start: Int, end: Int) -> List[T]
fn sort_ints(values: List[Int]) -> List[Int]
fn sort_strings(values: List[String]) -> List[String]
fn sorted[T](values: List[T], compare: fn(left: T, right: T) -> Int) -> List[T]
fn union[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## `@std/regex.ms`

```manuscript
fn compile(pattern: String) -> Result[Regex, RegexError]
fn find_all(pattern: Regex, text: String, max_matches: Int) -> Result[List[String], RegexError]
fn matches(pattern: Regex, text: String) -> Bool
fn replace(pattern: Regex, text: String, replacement: String, max_bytes: Int) -> Result[String, RegexError]
```

## Text behavior

Text is valid UTF-8. Scalar operations count Unicode code points, rather than bytes or user-perceived characters such as a letter plus a combining mark.

- `from_scalars` rejects surrogate code points and values outside the Unicode range.
- `slice_scalars` uses a half-open range: include `start`, exclude `end`. Invalid bounds return `OutOfRange`.
- `trim` uses Unicode White_Space. `upper` and `lower` use Go's locale-independent Unicode mappings; they do not normalize combining sequences.
- `split` keeps empty parts. It requires positive `max_parts`; the final part contains any remainder. An empty separator splits Unicode scalars.
- `replace` uses literal text. `max_replacements` must be nonnegative; zero means no replacements. An empty `old` inserts at scalar boundaries.
- `repeat` requires nonnegative `count` and `max_bytes`. It checks the size multiplication before allocating.
- An empty search string succeeds for contains, prefix, and suffix checks.

## Bytes and collections

Byte and collection slices also use half-open ranges. Negative, reversed, or out-of-range bounds produce a programming fault. `values` returns each unsigned byte as an `Int`.

Collection updates mutate their receiver. Algorithms such as map, filter, slice, and sorted return new values. Use `.clone()` before an update to retain a separate copy; nested references remain shared.

| Operation | Ordering rule |
| --- | --- |
| `map`, `filter`, `fold` | Callbacks run sequentially in input order, with ordinary cancellation and fault behavior. |
| `sorted` | Sorting is stable. The comparator returns a negative, zero, or positive `Int` and must define a consistent total preorder. Its call order and call count are unspecified. |
| `map_keys`, `map_values` | Preserve insertion order. |
| Set intersection and difference | Preserve the left set's order. |
| Set union | Keep left order, then append previously absent right values. |

You may explicitly specialize a generic function and store it as a function value. These operations add no compiler bounds.

## Encodings

Hex output uses lowercase. Hex input accepts either case but rejects odd digit counts and whitespace.

Base64 uses padded standard or URL-safe encoding according to `url_safe`. Decoding rejects whitespace, the wrong alphabet, malformed padding, and nonzero unused bits. `max_bytes` must be nonnegative; excess decoded output returns `LimitExceeded`.

`Bytes.to_text` strictly decodes UTF-8. Invalid text is an error; there is no decoder that silently substitutes replacement characters.

## Binary numbers

Integer widths are 1, 2, 4, or 8 bytes. Signed integers use two's complement. An unsigned 64-bit input above `MaxInt64` returns `OutOfRange`.

Invalid widths return `InvalidInput`. Bad offsets, truncated input, and values that cannot fit the requested representation return `OutOfRange`. Float reads and writes use IEEE binary64. `little_endian: true` explicitly selects little-endian order. These functions do not reinterpret unsafe memory or convert numeric types implicitly.

## Regular expressions

`Regex` is an opaque, immutable compiled Go RE2-style pattern. Backreferences and lookaround are invalid; compile failures return `InvalidData`.

`find_all` returns whole matches. `max_matches` must be nonnegative, and exceeding it returns `LimitExceeded` instead of a truncated success. Go regexp rules govern zero-width and adjacent matches.

`replace` uses literal replacement text, without `$` capture interpolation. It enforces `max_bytes` and never returns a partial output as success.

The string module also provides bounded Unicode normalization; see [JavaScript built-in coverage](javascript-builtins.md). Grapheme segmentation, non-UTF-8 codecs, and capture-group match records remain future work.
