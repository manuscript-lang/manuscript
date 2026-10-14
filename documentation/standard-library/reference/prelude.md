+++
title = "prelude"
+++

# prelude

Names available in every module; no import required.

## Bool {data-api-kind="Type"}

Boolean truth values true and false; conditions require this type.

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

Binary floating-point values, including signed zero, infinities and NaN.

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

Signed whole numbers with checked arithmetic; overflow and division by zero fault.

```manuscript
type Int:
    fn to_string(radix: Int) -> String:
    fn to_float() -> Float:
    fn to_decimal() -> Decimal:
```

### Int.to_decimal

Converts to the exactly equal Decimal; no rounding occurs.

```manuscript
fn to_decimal() -> Decimal
```

### Int.to_float

Converts to the nearest Float; integers beyond 2^53 in magnitude can lose low-order digits.

```manuscript
fn to_float() -> Float
```

### Int.to_string

Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
A radix outside 2 through 36 is a programming fault.

```manuscript
fn to_string(radix: Int) -> String
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
    fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
    fn take(count: Int) -> List[T]:
    fn drop(count: Int) -> List[T]:
    fn reverse_in_place() -> List[T]:
    fn reversed() -> List[T]:
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
    fn splice(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
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

### List.append

Adds `value` at the end in place and returns this same list.

```manuscript
fn append(value: T) -> List[T]:
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

### List.concat

Returns a new list holding this list's elements followed by `values`; neither operand is changed.

```manuscript
fn concat(values: List[T]) -> List[T]:
```

### List.contains

Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns false.

```manuscript
fn contains(value: T) -> Bool:
```

### List.copy_within

Copies the elements in [start, end) to begin at index `target`, in place, and returns this list.
The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length() and a target must be within 0 through length(); otherwise the call faults.

```manuscript
fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
```

### List.drop

Copies the remainder after min(count, length) into fresh shallow List storage.
Leaves the receiver unchanged; negative count is a programming fault.

```manuscript
fn drop(count: Int) -> List[T]:
```

### List.entries

Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.

```manuscript
fn entries() -> List[ListEntry[T]]:
```

### List.every

Returns true when every value satisfies the predicate; empty lists return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.fill

Sets elements in [start, end) to `value` in place and returns this list.
Bounds must satisfy 0 <= start <= end <= length(); negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.

```manuscript
fn fill(value: T, start: Int, end: Int) -> List[T]:
```

### List.filter

Keeps matching values in their original order.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
```

### List.find

Returns the first element for which `predicate` is true, or none; later elements are not tested after a match.

```manuscript
fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### List.find_index

Returns the zero-based index of the first element for which `predicate` is true, or none.

```manuscript
fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
```

### List.find_last

Searches from the end and returns the last element for which `predicate` is true, or none.

```manuscript
fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### List.find_last_index

Searches from the end and returns the last matching zero-based index, or none.

```manuscript
fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
```

### List.first

Returns the first element, or none when the list is empty.

```manuscript
fn first() -> Optional[T]:
```

### List.flat_map[U]

Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.

```manuscript
fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
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

Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.

```manuscript
fn for_each(operation: fn(value: T) -> Unit) -> Unit:
```

### List.group_by[K: Hashable]

Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
Keys appear in first-seen order and each group keeps the original element order.

```manuscript
fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
```

### List.index_of

Returns the first equal element's zero-based index, or none; elements require Equal.

```manuscript
fn index_of(value: T) -> Optional[Int]:
```

### List.is_empty

Reports whether the list has no elements.

```manuscript
fn is_empty() -> Bool:
```

### List.join

Concatenates the strings with `separator` between neighbors; an empty list returns an empty string.
Available only on List[String].

```manuscript
fn join(separator: String) -> String:
```

### List.keys

Returns a new list of the zero-based indexes 0 through length() - 1.

```manuscript
fn keys() -> List[Int]:
```

### List.last

Returns the last element, or none when the list is empty.

```manuscript
fn last() -> Optional[T]:
```

### List.last_index_of

Returns the last equal element's zero-based index, or none; elements require Equal.

```manuscript
fn last_index_of(value: T) -> Optional[Int]:
```

### List.length

Returns the number of elements.

```manuscript
fn length() -> Int:
```

### List.map[U]

Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> List[U]:
```

### List.prepend

Inserts `value` at index 0 in place, shifting existing elements one position later, and returns this same list.

```manuscript
fn prepend(value: T) -> List[T]:
```

### List.remove

Removes an element in place and returns this list; negative indexes count from the end.
Invalid indexes fault.
Shifts the suffix without clearing prior values retained in spare backing capacity.

```manuscript
fn remove(index: Int) -> List[T]:
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
Invalid indexes fault.

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

### List.splice

Replaces delete_count elements starting at start, mutating and returning this List.
Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
Replacement references stay shallow; using this same List as replacement stages its prior values.
Shrinking retains prior values in spare backing capacity, following captured Go slice traversal.

```manuscript
fn splice(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
```

### List.take

Copies the first min(count, length) elements into fresh shallow List storage.
Leaves the receiver unchanged; negative count is a programming fault.

```manuscript
fn take(count: Int) -> List[T]:
```

### List.to_set

Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.

```manuscript
fn to_set() -> Set[T]:
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
    fn add_default(key: T, value: U) -> Map[T, U]:
    fn add_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
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
    fn remove(key: T) -> Map[T, U]:
```

### Map.add

Inserts or replaces a value and returns this map; replacement keeps the original key and insertion position.

```manuscript
fn add(key: T, value: U) -> Map[T, U]:
```

### Map.add_default

Inserts a default only when the key is absent and returns this map.
The supplied value evaluates normally even when the key already exists.

```manuscript
fn add_default(key: T, value: U) -> Map[T, U]:
```

### Map.add_default_from

Creates and inserts a default only when the key is absent, then returns this map.
Calls create(key:) once for absence; an existing key leaves its value and position unchanged.

```manuscript
fn add_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
```

### Map.clear

Removes every entry in place and returns this same map; aliases observe the empty map.

```manuscript
fn clear() -> Map[T, U]:
```

### Map.clone

Returns a shallow copy with independent map storage.

```manuscript
fn clone() -> Map[T, U]:
```

### Map.contains

Reports whether an equal key is present, using the key type's Hashable implementation.

```manuscript
fn contains(key: T) -> Bool:
```

### Map.entries

Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.

```manuscript
fn entries() -> List[MapEntry[T, U]]:
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

### Map.get

Returns the value stored for an equal key, or none when the key is absent.

```manuscript
fn get(key: T) -> Optional[U]:
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

### Map.keys

Returns a new list of the keys in insertion order.

```manuscript
fn keys() -> List[T]:
```

### Map.length

Returns the number of entries.

```manuscript
fn length() -> Int:
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

### Map.merge

Copies every entry of `other` into this map in place and returns this map.
Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.

```manuscript
fn merge(other: Map[T, U]) -> Map[T, U]:
```

### Map.remove

Removes an equal key and returns this same Map; remaining entries retain insertion order.
An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.

```manuscript
fn remove(key: T) -> Map[T, U]:
```

### Map.some

Stops at the first matching entry; empty maps return false.

```manuscript
fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
```

### Map.values

Returns a new list of the values in insertion order.

```manuscript
fn values() -> List[U]:
```

## Never {data-api-kind="Type"}

The return type of computations that cannot return a value, such as panic.

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

### Optional.none

An absent value with no payload; no T needs to be constructed.

```manuscript
case none
```

### Optional.some

A present payload, retained by reference when T is mutable.

```manuscript
case some(value: T)
```

### Optional.some.value

The contained value; unwrap and matching return this original payload.

```manuscript
value: T
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

Returns true for some(value), and false for none.

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

### Result.error

An expected failure value; it is distinct from faults and cancellation.

```manuscript
case error(cause: E)
```

### Result.ok

A successful result, retaining its payload without a deep copy.

```manuscript
case ok(value: T)
```

### Result.error.cause

The original domain error, retained through compatible Result propagation.

```manuscript
cause: E
```

### Result.ok.value

The successful value returned by unwrap, matching, or propagation.

```manuscript
value: T
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

## Set {data-api-kind="Native type"}

A mutable collection of unique values using explicit `Hashable` value semantics.

```manuscript
type Set[T: Hashable]:
    fn clone() -> Set[T]:
    fn is_empty() -> Bool:
    fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
    fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn union(right: Set[T]) -> Set[T]:
    fn intersection(right: Set[T]) -> Set[T]:
    fn difference(right: Set[T]) -> Set[T]:
    fn symmetric_difference(right: Set[T]) -> Set[T]:
    fn is_subset_of(right: Set[T]) -> Bool:
    fn is_superset_of(right: Set[T]) -> Bool:
    fn is_disjoint_from(right: Set[T]) -> Bool:
    fn clear() -> Set[T]:
    fn values() -> List[T]:
    fn entries() -> List[List[T]]:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn contains(value: T) -> Bool:
    fn length() -> Int:
    fn add(value: T) -> Set[T]:
    fn remove(value: T) -> Set[T]:
```

### Set.add

Adds a value in place and returns this set; an equal value retains its original payload and position.

```manuscript
fn add(value: T) -> Set[T]:
```

### Set.clear

Removes all values in place and returns this set; aliases observe the empty set.

```manuscript
fn clear() -> Set[T]:
```

### Set.clone

Copies outer storage, retaining element references and insertion order.

```manuscript
fn clone() -> Set[T]:
```

### Set.contains

Reports whether an equal value is present, using the element's Hashable implementation.

```manuscript
fn contains(value: T) -> Bool:
```

### Set.difference

Returns a new set of receiver values absent from right, preserving receiver insertion order.

```manuscript
fn difference(right: Set[T]) -> Set[T]:
```

### Set.entries

Returns a new list of [value, value] lists in insertion order.

```manuscript
fn entries() -> List[List[T]]:
```

### Set.every

Stops at the first nonmatching element; empty sets return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### Set.filter

Copies matching elements in insertion order, retaining payload references.
Callbacks traverse a snapshot even when they mutate the receiver.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
```

### Set.find

Returns the original first matching element, or none.

```manuscript
fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### Set.find_last

Searches a snapshot from the end, returning the original last matching element.

```manuscript
fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### Set.fold[A]

Reduces an element snapshot in insertion order, starting with initial.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### Set.fold_right[A]

Reduces an element snapshot in reverse insertion order, starting with initial.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### Set.for_each

Calls operation(value:) sequentially over an insertion-order membership snapshot.

```manuscript
fn for_each(operation: fn(value: T) -> Unit) -> Unit:
```

### Set.intersection

Returns a new set of receiver values also in right, preserving receiver insertion order.

```manuscript
fn intersection(right: Set[T]) -> Set[T]:
```

### Set.is_disjoint_from

Tests whether the operands have no common values.

```manuscript
fn is_disjoint_from(right: Set[T]) -> Bool:
```

### Set.is_empty

Reports whether this set has no elements.

```manuscript
fn is_empty() -> Bool:
```

### Set.is_subset_of

Tests whether every receiver value also occurs in right.

```manuscript
fn is_subset_of(right: Set[T]) -> Bool:
```

### Set.is_superset_of

Tests whether every right value also occurs in the receiver.

```manuscript
fn is_superset_of(right: Set[T]) -> Bool:
```

### Set.length

Returns the number of distinct values currently stored.

```manuscript
fn length() -> Int:
```

### Set.map[U: Hashable]

Transforms a snapshot into a fresh set, retaining the first equal result.

```manuscript
fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
```

### Set.remove

Removes an equal value in place and returns this set; an absent value leaves it unchanged.

```manuscript
fn remove(value: T) -> Set[T]:
```

### Set.some

Stops at the first matching element; empty sets return false.

```manuscript
fn some(predicate: fn(value: T) -> Bool) -> Bool:
```

### Set.symmetric_difference

Returns a new set of values in exactly one operand; leaves both operands unchanged.

```manuscript
fn symmetric_difference(right: Set[T]) -> Set[T]:
```

### Set.union

Returns a new set with receiver values followed by right-only values in insertion order.

```manuscript
fn union(right: Set[T]) -> Set[T]:
```

### Set.values

Returns a shallow list of values in insertion order.

```manuscript
fn values() -> List[T]:
```

## String {data-api-kind="Type"}

UTF-8 text indexed by Unicode scalar values; byte_length counts encoded bytes instead.

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
    fn replace_n(old: String, new: String, max_replacements: Int) -> String:
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

Transitional compatibility name: omitted or none replaces the first occurrence; an explicit cap can replace more.
Use replace_n for a required finite cap; this retained signature has not become a strict first-only operation.
An empty old matches at scalar boundaries, and inserted text is not searched again.
Zero changes nothing; negative caps retain replace's programming fault.

```manuscript
fn replace_first(old: String, new: String, max_replacements: Optional[Int] = none) -> String
```

### String.replace_n

Replaces at most the required number of nonoverlapping literal occurrences; zero leaves text unchanged.
Empty old matches at scalar boundaries, inserted text is not rescanned, and negative caps retain replace's programming fault.
The count limits replacements, not UTF-8 output bytes; there is no additional allocation budget.

```manuscript
fn replace_n(old: String, new: String, max_replacements: Int) -> String
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

The single value unit, used when an operation returns no useful payload.

```manuscript
type Unit:
```

