# Canonical standard-library declarations. Implementations are native.

# Errors returned when a collection factory exceeds its supplied item limit.
export type CollectionError:
    case InvalidInput
    case LimitExceeded

# An ordered collection of values with indexing, iteration, and transformation operations.
export type List[T]:
    # Returns a shallow copy with independent list storage.
    fn clone() -> List[T]:
    # Returns an element; negative indexes are relative to the end, and out-of-range indexes return none.
    fn at(index: Int) -> Optional[T]:
    fn contains(value: T) -> Bool:
    # Returns the first equal element's zero-based index, or none; elements require Equal.
    fn index_of(value: T) -> Optional[Int]:
    # Returns the last equal element's zero-based index, or none; elements require Equal.
    fn last_index_of(value: T) -> Optional[Int]:
    fn first() -> Optional[T]:
    fn last() -> Optional[T]:
    fn is_empty() -> Bool:
    fn prepend(value: T) -> List[T]:
    fn with_value(index: Int, value: T) -> List[T]:
    fn without(index: Int) -> List[T]:
    # Returns a new shallow List containing [start, end); outer storage is independent.
    # Faults unless 0 <= start <= end <= length(); negative bounds are not relative.
    fn slice(start: Int, end: Int) -> List[T]:
    fn reverse() -> List[T]:
    # Returns a new list sorted by negative/zero/positive comparator results.
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    # Keeps matching values in their original order.
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    # Searches from the end and returns the last matching zero-based index, or none.
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    # Returns true when at least one value satisfies the predicate.
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    # Returns true when every value satisfies the predicate; empty lists return true.
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    # Calls operation(value:) sequentially over a membership snapshot; nested references remain shared.
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    # Reduces values from left to right, starting with `initial`.
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Reduces values from right to left, starting with `initial`.
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Replaces `delete_count` values at `start` with the replacement list.
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

# A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export type Map[T: Hashable, U]:
    # Returns a shallow copy with independent map storage.
    fn clone() -> Map[T, U]:
    # Reports whether this map has no entries.
    fn is_empty() -> Bool:
    # Copies matching entries in insertion order, retaining payload references.
    # Callbacks traverse a snapshot even when they mutate the receiver.
    fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
    # Returns the stored value or an eagerly evaluated fallback without inserting.
    fn get_or(key: T, fallback: U) -> U:
    # Sets `key` to `value` only when the key is absent.
    fn with_default(key: T, value: U) -> Map[T, U]:
    # Creates a value only when the key is absent.
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
    fn clear() -> Map[T, U]:
    fn keys() -> List[T]:
    fn values() -> List[U]:
    fn entries() -> List[MapEntry[T, U]]:
    fn merge(other: Map[T, U]) -> Map[T, U]:
    # Calls operation(key:, value:) sequentially over an insertion-order membership snapshot.
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
    fn contains(key: T) -> Bool:
    fn get(key: T) -> Optional[U]:
    fn length() -> Int:
    fn with_entry(key: T, value: U) -> Map[T, U]:
    fn without(key: T) -> Map[T, U]:

# One key-value pair returned by `Map.entries`.
export type MapEntry[T: Hashable, U]:
    key: T
    value: U

# A mutable collection of unique values using explicit `Hashable` value semantics.
export type Set[T: Hashable]:
    fn clone() -> Set[T]:
    # Reports whether this set has no elements.
    fn is_empty() -> Bool:
    # Copies matching elements in insertion order, retaining payload references.
    # Callbacks traverse a snapshot even when they mutate the receiver.
    fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
    # Transforms a snapshot into a fresh set, retaining the first equal result.
    fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
    fn union(right: Set[T]) -> Set[T]:
    fn intersection(right: Set[T]) -> Set[T]:
    fn difference(right: Set[T]) -> Set[T]:
    # Returns a new set of values in exactly one operand; leaves both operands unchanged.
    fn symmetric_difference(right: Set[T]) -> Set[T]:
    # Tests whether every receiver value also occurs in right.
    fn is_subset_of(right: Set[T]) -> Bool:
    # Tests whether every right value also occurs in the receiver.
    fn is_superset_of(right: Set[T]) -> Bool:
    # Tests whether the operands have no common values.
    fn is_disjoint_from(right: Set[T]) -> Bool:
    fn clear() -> Set[T]:
    # Returns a shallow list of values in insertion order.
    fn values() -> List[T]:
    # Returns a new list of [value, value] lists in insertion order.
    fn entries() -> List[List[T]]:
    # Calls operation(value:) sequentially over an insertion-order membership snapshot.
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn contains(value: T) -> Bool:
    fn length() -> Int:
    fn with_value(value: T) -> Set[T]:
    fn without(value: T) -> Set[T]:

# One list index and its corresponding value.
export type ListEntry[T]:
    index: Int
    value: T

# Creates a list containing `value` repeated `count` times.
export fn filled[T](
    value: T,
    count: Int,
    max_items: Optional[Int] = none
) -> Result[List[T], CollectionError]:

# Creates integers from `start` up to but excluding `end` using `step`.
export fn range(
    start: Int,
    end: Int,
    step: Int,
    max_items: Optional[Int] = none
) -> Result[List[Int], CollectionError]:

# Builds a map from entries. Later entries replace earlier values for duplicate keys.
export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]:

impl Error for CollectionError:
    fn message() -> String:

# Appends values efficiently before freezing them into a list.
export type ListBuilder[T]:
    fn append(value: T) -> Unit:
    fn freeze() -> List[T]:

# Adds entries efficiently before freezing them into a map.
export type MapBuilder[T: Hashable, U]:
    fn freeze() -> Map[T, U]:
    fn with_entry(key: T, value: U) -> Unit:

# Adds unique values efficiently before freezing them into a set.
export type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]:
    fn with_value(value: T) -> Unit:
