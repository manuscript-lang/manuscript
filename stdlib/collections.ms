# Errors returned when a collection factory exceeds its supplied item limit.
export type CollectionError:
    # A count, item budget, or step is invalid: `count` or `max_items` is negative, or `range_by` has a zero `step`.
    case InvalidInput
    # The result would hold more items than `max_items`, or more than the runtime's ceiling of 268435456 (2^28) items when `max_items` is omitted.
    case LimitExceeded
    # A slice bound lies outside 0 <= start <= end <= length() after negative bounds are resolved from the end.
    case OutOfRange

# An ordered mutable collection with indexing, iteration, and transformations.
# Primitive backing stores Int values at the platform's Int width and Float values at 64 bits, Bool values as bytes, and String references without an element box.
# Lists are owned values; clone makes a deep copy and accessors can borrow elements.
export type List[T]:

impl List[T]:
    # Returns a deep copy with independent list and nested value storage.
    fn clone() List[T]:

    # Returns an element; negative indexes are relative to the end. An out-of-range index returns `default`, and without one raises a fault.
    fn get(index: Int, default: Optional[T] = none) T:

    # Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns false.
    fn contains(value: T) Bool:

    # Returns the first equal element's zero-based index, or none; elements require Equal.
    fn index_of(value: T) Optional[Int]:

    # Returns the last equal element's zero-based index, or none; elements require Equal.
    fn last_index_of(value: T) Optional[Int]:

    # Returns the first element, or none when the list is empty.
    fn first() Optional[T]:

    # Returns the last element, or none when the list is empty.
    fn last() Optional[T]:

    # Reports whether the list has no elements.
    fn is_empty() Bool:

    # Inserts `value` at index 0 in place, shifting existing elements one position later.
    var fn prepend(value: T) Unit:

    # Inserts value before index in place; negative indexes count from the end.
    # Requires -length() <= index <= length(); index length() appends, and invalid indexes fault.
    var fn insert(index: Int, value: T) Unit:

    # Removes and returns the last element in place, or none for an empty list.
    var fn pop() Optional[T]:

    # Replaces an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    var fn set(index: Int, value: T) Unit:

    # Removes an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    # Shifts the suffix without clearing prior values retained in spare backing capacity.
    var fn remove(index: Int) Unit:

    # Returns a new owned List containing copies of the elements in [start, end).
    # Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    fn slice(start: Int, end: Int) Result[List[T], CollectionError]:

    # Copies the first min(count, length) elements into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn take(count: Int) List[T]:

    # Copies the remainder after min(count, length) into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn drop(count: Int) List[T]:

    # Reverses this list in place.
    var fn reverse_in_place() Unit:

    # Returns an independent reversed copy, including nested values.
    fn reversed() List[T]:

    # Returns a new list sorted by negative/zero/positive comparator results.
    fn sorted(compare: fn(left: T, right: T) Int) List[T]:

    # Keeps matching values in their original order.
    fn filter(predicate: fn(value: T) Bool) List[T]:

    # Returns the first element for which `predicate` is true, or none; later elements are not tested after a match.
    fn find(predicate: fn(value: T) Bool) Optional[T]:

    # Searches from the end and returns the last element for which `predicate` is true, or none.
    fn find_last(predicate: fn(value: T) Bool) Optional[T]:

    # Returns the zero-based index of the first element for which `predicate` is true, or none.
    fn find_index(predicate: fn(value: T) Bool) Optional[Int]:

    # Searches from the end and returns the last matching zero-based index, or none.
    fn find_last_index(predicate: fn(value: T) Bool) Optional[Int]:

    # Counts values satisfying the predicate, calling it once per element in order.
    fn count(predicate: fn(value: T) Bool) Int:

    # Returns a new owned List keeping a copy of each first equal element in order; elements require Equal.
    fn distinct() List[T]:

    # Returns true when at least one value satisfies the predicate.
    fn some(predicate: fn(value: T) Bool) Bool:

    # Returns true when every value satisfies the predicate; empty lists return true.
    fn every(predicate: fn(value: T) Bool) Bool:

    # Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.
    fn for_each(operation: fn(value: T) Unit) Unit:

    # Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
    # Keys appear in first-seen order and each group keeps the original element order.
    fn group_by[K: Hashable](key: fn(value: T) K) Map[K, List[T]]:

    # Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.
    fn map[U](transform: fn(value: T) U) List[U]:

    # Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.
    fn flat_map[U](transform: fn(value: T) List[U]) List[U]:

    # Reduces values from left to right, starting with `initial`.
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) A) A:

    # Reduces values from right to left, starting with `initial`.
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) A) A:

    # Replaces delete_count elements starting at start in place, consuming the replacement list and returning Unit.
    # Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
    # Removed elements are dropped; replacement elements move into the receiver. Overlapping receiver and replacement arguments are rejected.
    var fn splice(start: Int, delete_count: Int, replacement: List[T]) Unit:

    # Sets elements in [start, end) to `value` in place.
    # Bounds must satisfy 0 <= start <= end <= length(); negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.
    var fn fill(value: T, start: Int, end: Int) Unit:

    # Copies the elements in [start, end) to begin at index `target`, in place.
    # The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length() and a target must be within 0 through length(); otherwise the call faults.
    var fn copy_within(target: Int, start: Int, end: Int) Unit:

    # Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.
    fn to_set() Set[T]:

    # Returns a new list of the zero-based indexes 0 through length() - 1.
    fn keys() List[Int]:

    # Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.
    fn entries() List[ListEntry[T]]:

    # Concatenates the strings with `separator` between neighbors; an empty list returns an empty string.
    # Available only on List[String].
    fn join(separator: String) String:

    # Adds `value` at the end in place.
    var fn append(value: T) Unit:

    # Returns a new list holding this list's elements followed by `other`; neither operand is changed.
    fn concat(other: List[T]) List[T]:

    # Returns the number of elements.
    fn length() Int:

# A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export type Map[T: Hashable, U]:

impl Map[T, U]:
    # Returns a deep copy with independent map and nested value storage.
    fn clone() Map[T, U]:

    # Reports whether this map has no entries.
    fn is_empty() Bool:

    # Copies matching entries and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    fn filter(predicate: fn(key: T, value: U) Bool) Map[T, U]:

    # Transforms values in insertion order, retaining original keys.
    # Returns owned storage with copied keys and owned results.
    fn map[W](transform: fn(key: T, value: U) W) Map[T, W]:

    # Transforms keys in insertion order, copying values.
    # Equal outputs keep the first key/position and the last input value.
    fn map_keys[W: Hashable](transform: fn(key: T, value: U) W) Map[W, U]:

    # Returns the stored value or an eagerly evaluated fallback without inserting.
    fn get_or(key: T, fallback: U) U:

    # Reduces entries in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) A) A:

    # Reduces entries in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) A) A:

    # Returns the first matching entry as an owned record containing copies of the key and value.
    fn find(predicate: fn(key: T, value: U) Bool) Optional[MapEntry[T, U]]:

    # Searches from the end, stopping at the last matching entry.
    # Returns a fresh entry record containing copies of its key and value.
    fn find_last(predicate: fn(key: T, value: U) Bool) Optional[MapEntry[T, U]]:

    # Stops at the first matching entry; empty maps return false.
    fn some(predicate: fn(key: T, value: U) Bool) Bool:

    # Stops at the first nonmatching entry; empty maps return true.
    fn every(predicate: fn(key: T, value: U) Bool) Bool:

    # Inserts a default only when the key is absent.
    # The supplied value evaluates normally even when the key already exists.
    var fn add_default(key: T, value: U) Unit:

    # Creates and inserts a default only when the key is absent.
    # Calls create(key:) once for absence; an existing key leaves its value and position unchanged.
    var fn add_default_from(key: T, create: fn(key: T) U) Unit:

    # Removes every entry in place.
    var fn clear() Unit:

    # Returns a new list of the keys in insertion order.
    fn keys() List[T]:

    # Returns a new list of the values in insertion order.
    fn values() List[U]:

    # Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.
    fn entries() List[MapEntry[T, U]]:

    # Copies every entry of `other` into this map in place.
    # Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.
    var fn merge(other: Map[T, U]) Unit:

    # Calls operation(key:, value:) sequentially over the receiver in insertion order.
    fn for_each(operation: fn(key: T, value: U) Unit) Unit:

    # Reports whether an equal key is present, using the key type's Hashable implementation.
    fn contains(key: T) Bool:

    # Returns the value stored for an equal key, or none when the key is absent.
    fn get(key: T) Optional[U]:

    # Returns the number of entries.
    fn length() Int:

    # Inserts or replaces a value; replacement keeps the original key and insertion position.
    var fn add(key: T, value: U) Unit:

    # Removes an equal key in place; remaining entries retain insertion order.
    # An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.
    var fn remove(key: T) Unit:

# One key-value pair returned by `Map.entries`.
export type MapEntry[T: Hashable, U]:
    # The lookup identity of the pair; unique within its map under Hashable equality.
    key: T
    # The payload stored for `key`; accessing this field can borrow from the entry.
    value: U

# A mutable collection of unique values using explicit `Hashable` value semantics.
export type Set[T: Hashable]:

impl Set[T]:
    # Copies elements deeply into independent storage, retaining insertion order.
    fn clone() Set[T]:

    # Reports whether this set has no elements.
    fn is_empty() Bool:

    # Copies matching elements and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    fn filter(predicate: fn(value: T) Bool) Set[T]:

    # Transforms elements into a fresh set, retaining the first equal result.
    fn map[U: Hashable](transform: fn(value: T) U) Set[U]:

    # Reduces elements in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) A) A:

    # Reduces elements in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) A) A:

    # Returns the original first matching element, or none.
    fn find(predicate: fn(value: T) Bool) Optional[T]:

    # Searches from the end, returning the original last matching element.
    fn find_last(predicate: fn(value: T) Bool) Optional[T]:

    # Stops at the first matching element; empty sets return false.
    fn some(predicate: fn(value: T) Bool) Bool:

    # Stops at the first nonmatching element; empty sets return true.
    fn every(predicate: fn(value: T) Bool) Bool:

    # Returns a new set with receiver values followed by right-only values in insertion order.
    fn union(other: Set[T]) Set[T]:

    # Returns a new set of receiver values also in right, preserving receiver insertion order.
    fn intersection(other: Set[T]) Set[T]:

    # Returns a new set of receiver values absent from right, preserving receiver insertion order.
    fn difference(other: Set[T]) Set[T]:

    # Returns a new set of values in exactly one operand; leaves both operands unchanged.
    fn symmetric_difference(other: Set[T]) Set[T]:

    # Tests whether every receiver value also occurs in right.
    fn is_subset_of(other: Set[T]) Bool:

    # Tests whether every right value also occurs in the receiver.
    fn is_superset_of(other: Set[T]) Bool:

    # Tests whether the operands have no common values.
    fn is_disjoint_from(other: Set[T]) Bool:

    # Removes all values in place.
    var fn clear() Unit:

    # Returns an owned list containing copies of values in insertion order.
    fn values() List[T]:

    # Returns a new list of [value, value] lists in insertion order.
    fn entries() List[List[T]]:

    # Calls operation(value:) sequentially over the receiver in insertion order.
    fn for_each(operation: fn(value: T) Unit) Unit:

    # Reports whether an equal value is present, using the element's Hashable implementation.
    fn contains(value: T) Bool:

    # Returns the number of distinct values currently stored.
    fn length() Int:

    # Adds a value in place; an equal value retains its original payload and position.
    var fn add(value: T) Unit:

    # Removes an equal value in place; an absent value leaves it unchanged.
    var fn remove(value: T) Unit:

# One list index and its corresponding value.
export type ListEntry[T]:
    # Zero-based position of the element in the list that produced this entry.
    index: Int
    # The element found at `index`.
    value: T

# Creates a list containing `value` repeated `count` times.
export fn filled[T](
    value: T,
    count: Int,
    max_items: Optional[Int] = none
) Result[List[T], CollectionError]:

# Creates the integers from `start` up to but excluding `end`, counting by one. The list is empty when `end <= start`. `for index in range(0, count):` runs as a counter loop without allocating the list. As a stored list, more than about 268 million items is a fault; use `range_by` to bound the size with an error value.
export fn range(start: Int, end: Int) List[Int]:

# Creates integers from `start` up to but excluding `end` using a nonzero `step`; a negative step counts down. Returns `InvalidInput` for a zero step and `LimitExceeded` when the list would exceed `max_items`.
export fn range_by(
    start: Int,
    end: Int,
    step: Int,
    max_items: Optional[Int] = none
) Result[List[Int], CollectionError]:

# Builds a map from entries. Later entries replace earlier values for duplicate keys.
export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) Map[K, V]:

impl Error for CollectionError:
    # Returns the fixed diagnostic `collection: <reason>`, such as `collection: limit exceeded`, without echoing values.
    fn message() String:

# Appends values efficiently before freezing them into a list.
export type ListBuilder[T]:

impl ListBuilder[T]:
    # Adds `value` to the end of the mutable builder and returns Unit.
    # A frozen builder faults.
    fn append(value: T) Unit:

    # Seals the builder and returns the accumulated list without copying it.
    # Later `append` calls fault.
    fn freeze() List[T]:

# Adds entries efficiently before freezing them into a map.
export type MapBuilder[T: Hashable, U]:

impl MapBuilder[T, U]:
    # Seals the builder and returns the accumulated map without copying it.
    # Later `add` calls fault.
    fn freeze() Map[T, U]:

    # Inserts or replaces an entry in the mutable builder; returns Unit like all builder mutations.
    # Replacement retains the original key and insertion position; a sealed builder faults.
    fn add(key: T, value: U) Unit:

# Adds unique values efficiently before freezing them into a set.
export type SetBuilder[T: Hashable]:

impl SetBuilder[T]:
    # Seals the builder and returns the accumulated set without copying it.
    # Later `add` calls fault.
    fn freeze() Set[T]:

    # Adds a value to the mutable builder; returns Unit like all builder mutations.
    # Equal values retain the first payload and position; a sealed builder faults.
    fn add(value: T) Unit:

# Concatenates the inner lists in order into one new list (JavaScript `Array.prototype.flat`).
export fn flatten[T](lists: List[List[T]]) List[T]:
