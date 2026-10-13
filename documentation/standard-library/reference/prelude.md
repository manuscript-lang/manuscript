+++
title = "prelude"
+++

# prelude

Names available in every module; no import required.

## Bool {data-api-kind="Type"}

```manuscript
type Bool:
```

## Equal {data-api-kind="Interface"}

Equality and hashing are ordinary operation interfaces. Built-in data retains
its value semantics; an explicit implementation selects domain identity.

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool
```

### Equal.equals

Compares this value with another value in the same domain.

```manuscript
fn equals(other: Equal) -> Bool
```

## Error {data-api-kind="Interface"}

A contract for expected failures that can provide a human-readable message.

```manuscript
interface Error:
    fn message() -> String
```

### Error.message

Returns a human-readable description of this expected error.

```manuscript
fn message() -> String
```

## Float {data-api-kind="Type"}

```manuscript
type Float:
    fn to_precision(precision: Int) -> Result[String, NumberError]:
    fn to_exponential(digits: Int) -> Result[String, NumberError]:
    fn to_fixed(digits: Int) -> Result[String, NumberError]:
    fn to_string() -> String:
    fn is_nan() -> Bool:
    fn is_finite() -> Bool:
    fn truncate_to_int() -> Optional[Int]:
```

### Float.is_finite

Tests whether the value is neither NaN nor an infinity.

```manuscript
fn is_finite() -> Bool
```

### Float.is_nan

Tests whether the value is NaN.

```manuscript
fn is_nan() -> Bool
```

### Float.to_exponential

Formats scientific notation with 0..100 fractional digits; an invalid count returns NumberError.InvalidInput.

```manuscript
fn to_exponential(digits: Int) -> Result[String, NumberError]
```

### Float.to_fixed

Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
Invalid digits return NumberError.InvalidInput; rounding uses binary64 ties to even.

```manuscript
fn to_fixed(digits: Int) -> Result[String, NumberError]
```

### Float.to_precision

Formats 1..100 significant digits, preserving trailing zeros; an invalid precision returns NumberError.InvalidInput.

```manuscript
fn to_precision(precision: Int) -> Result[String, NumberError]
```

### Float.to_string

Returns the shortest round-trip representation, including NaN and signed infinities.

```manuscript
fn to_string() -> String
```

### Float.truncate_to_int

Truncates toward zero, or returns none for nonfinite values or Int overflow.

```manuscript
fn truncate_to_int() -> Optional[Int]
```

## Hashable {data-api-kind="Interface"}

A type with a stable hash consistent with its `Equal` implementation.

```manuscript
interface Hashable:
    fn hash() -> Int
```

### Hashable.hash

Returns a stable hash consistent with `equals` for the same value.

```manuscript
fn hash() -> Int
```

## Int {data-api-kind="Type"}

```manuscript
type Int:
    fn to_string(radix: Int) -> String:
    fn to_float() -> Float:
    fn to_decimal() -> Decimal:
```

## List {data-api-kind="Native type"}

An ordered collection of values with indexing, iteration, and transformation operations.

```manuscript
type List[T]:
    fn clone() -> List[T]:
    fn at(index: Int) -> Optional[T]:
    fn contains(value: T) -> Bool:
    fn index_of(value: T) -> Optional[Int]:
    fn last_index_of(value: T) -> Optional[Int]:
    fn first() -> Optional[T]:
    fn last() -> Optional[T]:
    fn is_empty() -> Bool:
    fn prepend(value: T) -> List[T]:
    fn set(index: Int, value: T) -> List[T]:
    fn remove(index: Int) -> List[T]:
    fn with_value(index: Int, value: T) -> List[T]:
    fn without(index: Int) -> List[T]:
    fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
    fn reverse_in_place() -> List[T]:
    fn reversed() -> List[T]:
    fn reverse() -> List[T]:
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
    fn fill(value: T, start: Int, end: Int) -> List[T]:
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
    fn to_set() -> Set[T]:
    fn keys() -> List[Int]:
    fn entries() -> List[ListEntry[T]]:
    fn join(separator: String) -> String:
    fn append(value: T) -> List[T]:
    fn concat(values: List[T]) -> List[T]:
    fn length() -> Int:
```

### List.at

Returns an element; negative indexes are relative to the end, and out-of-range indexes return none.

```manuscript
fn at(index: Int) -> Optional[T]:
```

### List.clone

Returns a shallow copy with independent list storage.

```manuscript
fn clone() -> List[T]:
```

### List.every

Returns true when every value satisfies the predicate; empty lists return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.filter

Keeps matching values in their original order.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
```

### List.find_last_index

Searches from the end and returns the last matching zero-based index, or none.

```manuscript
fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
```

### List.fold[A]

Reduces values from left to right, starting with `initial`.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### List.fold_right[A]

Reduces values from right to left, starting with `initial`.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### List.for_each

Calls operation(value:) sequentially over a membership snapshot; nested references remain shared.

```manuscript
fn for_each(operation: fn(value: T) -> Unit) -> Unit:
```

### List.index_of

Returns the first equal element's zero-based index, or none; elements require Equal.

```manuscript
fn index_of(value: T) -> Optional[Int]:
```

### List.last_index_of

Returns the last equal element's zero-based index, or none; elements require Equal.

```manuscript
fn last_index_of(value: T) -> Optional[Int]:
```

### List.remove

Removes an element in place and returns this list; negative indexes count from the end.
Invalid indexes fault, with the same bounds and diagnostics as without.

```manuscript
fn remove(index: Int) -> List[T]:
```

### List.reverse

Compatibility spelling for reverse_in_place; mutates and returns this list.

```manuscript
fn reverse() -> List[T]:
```

### List.reverse_in_place

Reverses this list in place and returns the same instance.

```manuscript
fn reverse_in_place() -> List[T]:
```

### List.reversed

Returns a reversed shallow copy with independent outer storage; nested references remain shared.

```manuscript
fn reversed() -> List[T]:
```

### List.set

Replaces an element in place and returns this list; negative indexes count from the end.
Invalid indexes fault, with the same bounds and diagnostics as with_value.

```manuscript
fn set(index: Int, value: T) -> List[T]:
```

### List.slice

Returns a new shallow List containing [start, end); outer storage is independent.
Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.

```manuscript
fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
```

### List.some

Returns true when at least one value satisfies the predicate.

```manuscript
fn some(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.sorted

Returns a new list sorted by negative/zero/positive comparator results.

```manuscript
fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
```

### List.with_value

Compatibility spelling for set; mutates and returns this list.

```manuscript
fn with_value(index: Int, value: T) -> List[T]:
```

### List.with_values

Replaces `delete_count` values at `start` with the replacement list.

```manuscript
fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
```

### List.without

Compatibility spelling for remove; mutates and returns this list.

```manuscript
fn without(index: Int) -> List[T]:
```

## Map {data-api-kind="Native type"}

A mutable key-value collection. Keys use explicit `Hashable` value semantics.

```manuscript
type Map[T: Hashable, U]:
    fn clone() -> Map[T, U]:
    fn is_empty() -> Bool:
    fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
    fn map[W](transform: fn(key: T, value: U) -> W) -> Map[T, W]:
    fn map_keys[W: Hashable](transform: fn(key: T, value: U) -> W) -> Map[W, U]:
    fn get_or(key: T, fallback: U) -> U:
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn find_last(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn with_default(key: T, value: U) -> Map[T, U]:
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
    fn clear() -> Map[T, U]:
    fn keys() -> List[T]:
    fn values() -> List[U]:
    fn entries() -> List[MapEntry[T, U]]:
    fn merge(other: Map[T, U]) -> Map[T, U]:
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
    fn contains(key: T) -> Bool:
    fn get(key: T) -> Optional[U]:
    fn length() -> Int:
    fn add(key: T, value: U) -> Map[T, U]:
    fn with_entry(key: T, value: U) -> Map[T, U]:
    fn without(key: T) -> Map[T, U]:
```

### Map.add

Inserts or replaces a value and returns this map; replacement keeps the original key and insertion position.

```manuscript
fn add(key: T, value: U) -> Map[T, U]:
```

### Map.clone

Returns a shallow copy with independent map storage.

```manuscript
fn clone() -> Map[T, U]:
```

### Map.every

Stops at the first nonmatching entry; empty maps return true.

```manuscript
fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
```

### Map.filter

Copies matching entries in insertion order, retaining payload references.
Callbacks traverse a snapshot even when they mutate the receiver.

```manuscript
fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
```

### Map.find

Returns the first matching entry as a fresh record with shallow references.

```manuscript
fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
```

### Map.find_last

Searches a snapshot from the end, stopping at the last matching entry.
Returns a fresh entry record retaining its original key/value references.

```manuscript
fn find_last(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
```

### Map.fold[A]

Reduces an entry snapshot in insertion order, starting with initial.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
```

### Map.fold_right[A]

Reduces an entry snapshot in reverse insertion order, starting with initial.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
```

### Map.for_each

Calls operation(key:, value:) sequentially over an insertion-order membership snapshot.

```manuscript
fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
```

### Map.get_or

Returns the stored value or an eagerly evaluated fallback without inserting.

```manuscript
fn get_or(key: T, fallback: U) -> U:
```

### Map.is_empty

Reports whether this map has no entries.

```manuscript
fn is_empty() -> Bool:
```

### Map.map[W]

Transforms values in snapshot insertion order, retaining original keys.
Returns independent outer storage with shallow key and result references.

```manuscript
fn map[W](transform: fn(key: T, value: U) -> W) -> Map[T, W]:
```

### Map.map_keys[W: Hashable]

Transforms keys in snapshot insertion order, retaining value references.
Equal outputs keep the first key/position and the last input value.

```manuscript
fn map_keys[W: Hashable](transform: fn(key: T, value: U) -> W) -> Map[W, U]:
```

### Map.some

Stops at the first matching entry; empty maps return false.

```manuscript
fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
```

### Map.with_default

Sets `key` to `value` only when the key is absent.

```manuscript
fn with_default(key: T, value: U) -> Map[T, U]:
```

### Map.with_default_from

Creates a value only when the key is absent.

```manuscript
fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
```

### Map.with_entry

Compatible spelling of add, with the same mutation and receiver return.

```manuscript
fn with_entry(key: T, value: U) -> Map[T, U]:
```

## Never {data-api-kind="Type"}

```manuscript
type Never:
```

## Optional {data-api-kind="Alternative"}

Represents a value that may be absent: `some(value)` or `none`.

```manuscript
type Optional[T]:
    case some(value: T)
    case none
    fn is_some() -> Bool:
    fn is_none() -> Bool:
    fn unwrap() -> T:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn() -> T) -> T:
    fn map[U](transform: fn(value: T) -> U) -> Optional[U]:
    fn and_then[U](transform: fn(value: T) -> Optional[U]) -> Optional[U]:
    fn or_else(create: fn() -> Optional[T]) -> Optional[T]:
    fn ok_or[E](cause: E) -> Result[T, E]:
    fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:
```

### Optional.and_then[U]

Calls transform only when present, returning its Optional unchanged.

```manuscript
fn and_then[U](transform: fn(value: T) -> Optional[U]) -> Optional[U]:
```

### Optional.is_none

Reports whether this value is absent.

```manuscript
fn is_none() -> Bool:
```

### Optional.is_some

Reports whether this value contains a payload.

```manuscript
fn is_some() -> Bool:
```

### Optional.map[U]

Transforms a present payload; none remains absent.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> Optional[U]:
```

### Optional.ok_or[E]

Returns ok with the original payload, or error with the eager cause.

```manuscript
fn ok_or[E](cause: E) -> Result[T, E]:
```

### Optional.ok_or_else[E]

Constructs an error once only for none; present payloads remain unchanged.

```manuscript
fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:
```

### Optional.or_else

Calls create once only when absent, returning its Optional unchanged.

```manuscript
fn or_else(create: fn() -> Optional[T]) -> Optional[T]:
```

### Optional.unwrap

Returns the payload. Calling this on `none` raises a fault.

```manuscript
fn unwrap() -> T:
```

### Optional.unwrap_or

Returns the contained value, or `fallback` when this is `none`.

```manuscript
fn unwrap_or(fallback: T) -> T:
```

### Optional.unwrap_or_else

Computes a fallback only when this is `none`.

```manuscript
fn unwrap_or_else(create: fn() -> T) -> T:
```

## Result {data-api-kind="Alternative"}

Holds either a successful value (`ok`) or an expected failure (`error`).

```manuscript
type Result[T, E]:
    case ok(value: T)
    case error(cause: E)
    fn is_ok() -> Bool:
    fn is_error() -> Bool:
    fn unwrap() -> T:
    fn unwrap_error() -> E:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn(cause: E) -> T) -> T:
    fn map[U](transform: fn(value: T) -> U) -> Result[U, E]:
    fn and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]:
    fn to_optional() -> Optional[T]:
```

### Result.and_then[U]

Calls transform only on success. Its result keeps the same error type.

```manuscript
fn and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]:
```

### Result.is_error

Reports whether this result contains an expected error.

```manuscript
fn is_error() -> Bool:
```

### Result.is_ok

Reports whether this result contains a successful value.

```manuscript
fn is_ok() -> Bool:
```

### Result.map[U]

Transforms only a successful payload, preserving an error unchanged.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> Result[U, E]:
```

### Result.to_optional

Returns some with the original success payload, or none for an error.

```manuscript
fn to_optional() -> Optional[T]:
```

### Result.unwrap

Returns the successful payload; faults when this is an error.

```manuscript
fn unwrap() -> T:
```

### Result.unwrap_error

Returns the error payload; faults when this is successful.

```manuscript
fn unwrap_error() -> E:
```

### Result.unwrap_or

Returns the successful payload, or the eagerly evaluated fallback.

```manuscript
fn unwrap_or(fallback: T) -> T:
```

### Result.unwrap_or_else

Calls create once with the original error only when this is an error.

```manuscript
fn unwrap_or_else(create: fn(cause: E) -> T) -> T:
```

## String {data-api-kind="Type"}

```manuscript
type String:
    fn length() -> Int:
    fn is_empty() -> Bool:
    fn chars() -> List[String]:
    fn reverse() -> String:
    fn compare(other: String) -> Int:
    fn lines() -> List[String]:
    fn normalize(form: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn concat(values: String) -> String:
    fn contains(text: String) -> Bool:
    fn ends_with(suffix: String) -> Bool:
    fn lower() -> String:
    fn repeat(count: Int, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn replace_first(old: String, new: String, max_replacements: Optional[Int] = none) -> String:
    fn replace(old: String, new: String, max_replacements: Optional[Int] = none) -> String:
    fn scalar_length() -> Int:
    fn scalar_values() -> List[Int]:
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]:
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]:
    fn starts_with(prefix: String) -> Bool:
    fn trim() -> String:
    fn upper() -> String:
    fn at(index: Int) -> Optional[String]:
    fn scalar_at(index: Int) -> Optional[Int]:
    fn index_of(value: String) -> Optional[Int]:
    fn last_index_of(value: String) -> Optional[Int]:
    fn trim_start() -> String:
    fn trim_end() -> String:
    fn pad_start(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn pad_end(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn replace_all(old: String, new: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn slice(start: Int, end: Int) -> Result[String, StringError]:
    fn byte_length() -> Int:
    fn to_bytes() -> Bytes:
    fn parse_int() -> Optional[Int]:
```

### String.at

Returns a one-scalar String; negative indexes are relative to the end, and invalid indexes return none.

```manuscript
fn at(index: Int) -> Optional[String]
```

### String.byte_length

Returns the UTF-8 encoded byte length.

```manuscript
fn byte_length() -> Int
```

### String.chars

Returns a fresh list with one String for each Unicode scalar, in order.

```manuscript
fn chars() -> List[String]
```

### String.compare

Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.

```manuscript
fn compare(other: String) -> Int
```

### String.concat

Concatenates text without changing either operand.

```manuscript
fn concat(values: String) -> String
```

### String.contains

Tests whether the exact text occurs, without normalization.

```manuscript
fn contains(text: String) -> Bool
```

### String.ends_with

Tests whether the receiver ends with this exact suffix.

```manuscript
fn ends_with(suffix: String) -> Bool
```

### String.index_of

Returns the first matching Unicode scalar index or none; empty value matches at zero.

```manuscript
fn index_of(value: String) -> Optional[Int]
```

### String.is_empty

Reports whether the text contains no scalars.

```manuscript
fn is_empty() -> Bool
```

### String.last_index_of

Returns the last matching Unicode scalar index or none; empty value matches at scalar_length().

```manuscript
fn last_index_of(value: String) -> Optional[Int]
```

### String.length

Counts Unicode scalars, with the same unit as scalar_length.

```manuscript
fn length() -> Int
```

### String.lines

Splits LF and CRLF lines, preserving interior empty lines and standalone CR.
Omits a final extra empty item; empty text returns a fresh empty list.

```manuscript
fn lines() -> List[String]
```

### String.lower

Returns locale-independent full Unicode lowercase mapping; the scalar length can change.

```manuscript
fn lower() -> String
```

### String.normalize

Normalizes using exactly NFC, NFD, NFKC, or NFKD (case-sensitive); max_bytes optionally bounds UTF-8 output.
Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.

```manuscript
fn normalize(form: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]
```

### String.pad_end

Pads on the right until the scalar length reaches `target_length`.
Empty padding or a shorter target leaves text unchanged; negative targets/budgets return InvalidInput.

```manuscript
fn pad_end(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]
```

### String.pad_start

Pads on the left until the scalar length reaches `target_length`.
Empty padding or a shorter target leaves text unchanged; max_bytes still bounds UTF-8 output.

```manuscript
fn pad_start(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]
```

### String.parse_int

Parses signed ASCII decimal digits; invalid text or Int overflow returns none.

```manuscript
fn parse_int() -> Optional[Int]
```

### String.repeat

Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.

```manuscript
fn repeat(count: Int, max_bytes: Optional[Int] = none) -> Result[String, StringError]
```

### String.replace

Compatibility spelling for replace_first, including its explicit replacement cap.

```manuscript
fn replace(old: String, new: String, max_replacements: Optional[Int] = none) -> String
```

### String.replace_all

Replaces every nonoverlapping occurrence; empty old matches at each scalar boundary.
max_bytes bounds UTF-8 output; negatives return InvalidInput and exhaustion returns LimitExceeded.

```manuscript
fn replace_all(old: String, new: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]
```

### String.replace_first

Replaces the first occurrence when the cap is omitted or none; an explicit cap can replace more.
An empty old matches at scalar boundaries, and inserted text is not searched again.
Zero changes nothing; negative caps retain replace's programming fault.

```manuscript
fn replace_first(old: String, new: String, max_replacements: Optional[Int] = none) -> String
```

### String.reverse

Reverses Unicode scalar order; combining sequences/graphemes may change.

```manuscript
fn reverse() -> String
```

### String.scalar_at

Returns an integer scalar code point; negative indexes are relative to the end, and invalid indexes return none.

```manuscript
fn scalar_at(index: Int) -> Optional[Int]
```

### String.scalar_length

Returns the number of Unicode scalar values in the string.

```manuscript
fn scalar_length() -> Int
```

### String.scalar_values

Returns each Unicode scalar value as an integer.

```manuscript
fn scalar_values() -> List[Int]
```

### String.slice

Selects [start, end) in Unicode scalars; negative bounds are relative to the end.
Bounds outside 0 <= start <= end <= scalar_length() return StringError.OutOfRange; the receiver is unchanged.

```manuscript
fn slice(start: Int, end: Int) -> Result[String, StringError]
```

### String.slice_scalars

Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length().
Negative, inverted, or out-of-range bounds return StringError.OutOfRange.

```manuscript
fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
```

### String.split

Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.

```manuscript
fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]
```

### String.starts_with

Tests whether the receiver begins with this exact prefix.

```manuscript
fn starts_with(prefix: String) -> Bool
```

### String.to_bytes

Encodes the string as UTF-8 bytes.

```manuscript
fn to_bytes() -> Bytes
```

### String.trim

Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.

```manuscript
fn trim() -> String
```

### String.trim_end

Removes Unicode whitespace at the end.

```manuscript
fn trim_end() -> String
```

### String.trim_start

Removes Unicode whitespace at the start.

```manuscript
fn trim_start() -> String
```

### String.upper

Returns locale-independent full Unicode uppercase mapping; the scalar length can change.

```manuscript
fn upper() -> String
```

## Unit {data-api-kind="Type"}

```manuscript
type Unit:
```

