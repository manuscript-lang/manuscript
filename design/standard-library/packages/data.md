+++
title = "Text, bytes, and collections"
weight = 49
+++

# Text, bytes, and collections

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/text.ms`

```text
fn contains(value: String, text: String) -> Bool
fn ends_with(value: String, suffix: String) -> Bool
fn from_scalars(values: List[Int]) -> Result[String, LibraryError]
fn join(parts: List[String], separator: String) -> String
fn lower(text: String) -> String
fn repeat(text: String, count: Int, max_bytes: Int) -> Result[String, LibraryError]
fn replace(text: String, old: String, new: String, max_replacements: Int) -> String
fn scalar_length(text: String) -> Int
fn scalar_values(text: String) -> List[Int]
fn slice_scalars(text: String, start: Int, end: Int) -> Result[String, LibraryError]
fn split(text: String, separator: String, max_parts: Int) -> List[String]
fn starts_with(value: String, prefix: String) -> Bool
fn trim(text: String) -> String
fn upper(text: String) -> String
```

## `@std/bytes.ms`

```text
fn contains(data: Bytes, value: Bytes) -> Bool
fn slice(data: Bytes, start: Int, end: Int) -> Bytes
fn values(data: Bytes) -> List[Int]
```

## `@std/encoding.ms`

```text
fn base64_decode(text: String, url_safe: Bool, max_bytes: Int) -> Result[Bytes, LibraryError]
fn base64_encode(data: Bytes, url_safe: Bool) -> String
fn hex_decode(text: String, max_bytes: Int) -> Result[Bytes, LibraryError]
fn hex_encode(data: Bytes) -> String
```

## `@std/binary.ms`

```text
fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, LibraryError]
fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int, LibraryError]
fn write_float(value: Float, little_endian: Bool) -> Bytes
fn write_integer(value: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, LibraryError]
```

## `@std/collections.ms`

```text
fn difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
fn filter[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> List[T]
fn fold[T: Shareable, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A
fn intersection[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
fn map[T: Shareable, U: Shareable](values: List[T], transform: fn(value: T) -> U) -> List[U]
fn map_keys[K: Hashable, V: Shareable](values: Map[K, V]) -> List[K]
fn map_values[K: Hashable, V: Shareable](values: Map[K, V]) -> List[V]
fn reverse[T: Shareable](values: List[T]) -> List[T]
fn slice[T: Shareable](values: List[T], start: Int, end: Int) -> List[T]
fn sort_ints(values: List[Int]) -> List[Int]
fn sort_strings(values: List[String]) -> List[String]
fn sorted[T: Shareable](values: List[T], compare: fn(left: T, right: T) -> Int) -> List[T]
fn union[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## `@std/regex.ms`

```text
fn compile(pattern: String) -> Result[Regex, LibraryError]
fn find_all(pattern: Regex, text: String, max_matches: Int) -> Result[List[String], LibraryError]
fn matches(pattern: Regex, text: String) -> Bool
fn replace(pattern: Regex, text: String, replacement: String, max_bytes: Int) -> Result[String, LibraryError]
```

## Behavior

Text remains valid UTF-8; scalar functions use Unicode code points, not bytes or grapheme clusters. From_scalars rejects surrogates/out-of-range values; slice_scalars returns OutOfRange for invalid half-open ranges. Trim uses Unicode White_Space; upper/lower use locale-independent Go Unicode mappings. These mappings do not normalize combining sequences. Split preserves empty parts and requires a nonempty separator and positive max_parts; its final part retains the remainder. Replacement is literal, requires nonempty old and nonnegative max_replacements; zero replaces nothing. Repeat requires nonnegative count/max_bytes and checks multiplication before allocation. Empty contains/prefix/suffix matches succeed.

Bytes slice and collection slice use half-open bounds and fault on negative/reversed/out-of-range indexes. Values returns unsigned bytes as Int. Updates/algorithms return new immutable values. Map/filter/fold invoke callbacks sequentially in input order and preserve ordinary cancellation/fault propagation. Sorted is stable; compare returns negative/zero/positive Int and must define a consistent total preorder. No comparator call order/count is promised. Map keys/values retain insertion order. Set intersection/difference retain left order; union appends previously absent right values. Generic functions may be explicitly specialized and stored as function values; they introduce no new compiler bounds.

Hex uses lowercase output, accepts either case on input, and rejects odd digits or whitespace. Base64 is padded standard or URL-safe according to url_safe; decoder rejects whitespace, wrong alphabet, malformed padding, and nonzero unused bits. Nonnegative max_bytes bounds decoded output; excess returns LimitExceeded. Existing Bytes.to_text is strict UTF-8 decoding; there is no replacement decoder.

Binary integer widths are 1/2/4/8 bytes; signed values use two's complement. Unsigned 64-bit input above MaxInt64 returns OutOfRange. Invalid widths return InvalidInput; offset/truncation/representation errors return OutOfRange. Float reads/writes are IEEE binary64. Endianness is explicit; true means little endian. No unsafe memory reinterpretation or implicit numeric conversion.

Regex is an opaque immutable/shareable Go RE2-style compiled pattern. Backreferences/lookaround are invalid; there is no JavaScript backtracking engine. Compile errors return InvalidData. Find_all returns whole matches, is bounded by nonnegative max_matches, and returns LimitExceeded rather than truncating. Go regexp zero-width advancement/adjacent-match rules apply. Replace uses literal replacement (no `$` capture interpolation), enforces max_bytes, and never exposes a partial successful result. Unicode normalization, grapheme segmentation, non-UTF-8 text codecs, and capture-group match records remain future additions.
