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
# `List[T]()` creates an empty list; `List[T](reserve: n)` also preallocates room for `n` items without changing the length. A negative `n` reserves nothing.
export type List[T]:
    # Constructor-only capacity hint in items: room for this many elements is allocated up front. The list starts empty; none or a negative value reserves nothing.
    reserve: Optional[Int] = none

impl List[T]:
    # Returns a deep copy with independent list and nested value storage.
    def clone() -> List[T]: ...

    # Returns an element; negative indexes are relative to the end. An out-of-range index returns `default`; pass one for indexes that may miss, or use `first()` and `last()`.
    # Without a default, an out-of-range index raises a fault, as `xs[i]` does.
    def get(index: Int, default: Optional[T] = none) -> ref T: ...

    # Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns False.
    def contains(value: T) -> Bool: ...

    # Returns the first equal element's zero-based index, or none; elements require Equal.
    def index_of(value: T) -> Optional[Int]: ...

    # Returns the last equal element's zero-based index, or none; elements require Equal.
    def last_index_of(value: T) -> Optional[Int]: ...

    # Returns the first element, or none when the list is empty.
    def first() -> ref Optional[T]: ...

    # Returns the last element, or none when the list is empty.
    def last() -> ref Optional[T]: ...

    # Reports whether the list has no elements.
    def is_empty() -> Bool: ...

    # Inserts `value` at index 0 in place, shifting existing elements one position later.
    var def prepend(value: T) -> Unit: ...

    # Inserts value before index in place; negative indexes count from the end.
    # Requires -length() <= index <= length(); index length() appends, and invalid indexes fault.
    var def insert(index: Int, value: T) -> Unit: ...

    # Removes and returns the last element in place, or none for an empty list.
    var def pop() -> Optional[T]: ...

    # Replaces an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    var def set(index: Int, value: T) -> Unit: ...

    # Removes an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    # Shifts the suffix without clearing prior values retained in spare backing capacity.
    var def remove(index: Int) -> Unit: ...

    # Returns a new owned List containing copies of the elements in [start, end).
    # Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    def slice(start: Int, end: Int) -> Result[List[T], CollectionError]: ...

    # Copies the first min(count, length) elements into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    def take(count: Int) -> List[T]: ...

    # Copies the remainder after min(count, length) into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    def drop(count: Int) -> List[T]: ...

    # Pairs elements by position into fresh `Pair` records, stopping at the shorter list; both lists are unchanged.
    def zip[U](other: List[U]) -> List[Pair[T, U]]: ...

    # Splits the list into consecutive copies of `size` elements; the last chunk may be shorter, and an empty list gives an empty list.
    # A `size` of zero or less is a programming fault.
    def chunks(size: Int) -> List[List[T]]: ...

    # Returns each run of `size` consecutive elements as an overlapping copy, in order; a list shorter than `size` gives an empty list.
    # A `size` of zero or less is a programming fault. Windows are copies: `slice` and `take` do not borrow today.
    def windows(size: Int) -> List[List[T]]: ...

    # Calls `predicate` once per element in order and splits the elements into those that matched and the rest, each keeping the original order.
    def partition(predicate: Callable[[T], Bool]) -> Partition[T]: ...

    # Reverses this list in place.
    var def reverse() -> Unit: ...

    # Returns an independent reversed copy, including nested values.
    def reversed() -> List[T]: ...

    # Returns a new list ordered by `compare`; the receiver is unchanged. The sort is stable: equal elements keep their order.
    # A negative, zero or positive result puts the first argument before, level with or after the second. Comparable elements also have `sorted()` without a comparator.
    # Example: `names.sorted(lambda a, b: a.length() - b.length())` orders by length.
    def sorted(compare: Callable[[T, T], Int]) -> List[T]: ...

    # Sorts the list in place, stably, in the order of `compare`, as `sorted` does. Comparable elements also have `sort()` without a comparator.
    # Example: `var xs = [3, 1, 2]` then `xs.sort(lambda a, b: b - a)` leaves `[3, 2, 1]`.
    var def sort(compare: Callable[[T, T], Int]) -> Unit: ...

    # Keeps matching values in their original order.
    def filter(predicate: Callable[[T], Bool]) -> List[T]: ...

    # Returns the first element for which `predicate` is True, or none; later elements are not tested after a match.
    def find(predicate: Callable[[T], Bool]) -> Optional[T]: ...

    # Searches from the end and returns the last element for which `predicate` is True, or none.
    def find_last(predicate: Callable[[T], Bool]) -> Optional[T]: ...

    # Returns the zero-based index of the first element for which `predicate` is True, or none.
    def find_index(predicate: Callable[[T], Bool]) -> Optional[Int]: ...

    # Searches from the end and returns the last matching zero-based index, or none.
    def find_last_index(predicate: Callable[[T], Bool]) -> Optional[Int]: ...

    # Counts values satisfying the predicate, calling it once per element in order.
    def count(predicate: Callable[[T], Bool]) -> Int: ...

    # Returns a new owned List keeping a copy of each first equal element in order; elements require Equal.
    def distinct() -> List[T]: ...

    # Returns True when at least one value satisfies the predicate.
    def any(predicate: Callable[[T], Bool]) -> Bool: ...

    # Returns True when every value satisfies the predicate; empty lists return True.
    def all(predicate: Callable[[T], Bool]) -> Bool: ...

    # Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.
    def for_each(operation: Callable[[T], Unit]) -> Unit: ...

    # Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
    # Keys appear in first-seen order and each group keeps the original element order.
    def group_by[K: Hashable](key: Callable[[T], K]) -> Map[K, List[T]]: ...

    # Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.
    def map[U](transform: Callable[[T], U]) -> List[U]: ...

    # Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.
    def flat_map[U](transform: Callable[[T], List[U]]) -> List[U]: ...

    # Reduces values from left to right, starting with `initial`.
    def fold[A](initial: A, step: Callable[[A, T], A]) -> A: ...

    # Reduces values from right to left, starting with `initial`.
    def fold_right[A](initial: A, step: Callable[[A, T], A]) -> A: ...

    # Replaces delete_count elements starting at start in place, consuming the replacement list and returning Unit.
    # Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
    # Removed elements are dropped; replacement elements move into the receiver. Overlapping receiver and replacement arguments are rejected.
    var def splice(start: Int, delete_count: Int, replacement: List[T]) -> Unit: ...

    # Sets elements in [start, end) to `value` in place.
    # Bounds must satisfy 0 <= start <= end <= length(); negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.
    var def fill(value: T, start: Int, end: Int) -> Unit: ...

    # Copies the elements in [start, end) to begin at index `target`, in place.
    # The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length() and a target must be within 0 through length(); otherwise the call faults.
    var def copy_within(target: Int, start: Int, end: Int) -> Unit: ...

    # Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.
    def to_set() -> Set[T]: ...

    # Returns a new list of the zero-based indexes 0 through length() - 1.
    def keys() -> List[Int]: ...

    # Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.
    def entries() -> List[ListEntry[T]]: ...

    # Concatenates the strings (or the decimal text of the integers) with `separator` between neighbors; an empty list returns an empty string.
    # Available only on List[String] and List[Int].
    def join(separator: String) -> String: ...

    # Adds `value` at the end in place.
    var def append(value: T) -> Unit: ...

    # Returns a new list holding this list's elements followed by `other`; neither operand is changed.
    def concat(other: List[T]) -> List[T]: ...

    # Returns the number of elements.
    def length() -> Int: ...

# A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export type Map[T: Hashable, U]: ...

impl Map[T, U]:
    # Returns a deep copy with independent map and nested value storage.
    def clone() -> Map[T, U]: ...

    # Reports whether this map has no entries.
    def is_empty() -> Bool: ...

    # Copies matching entries and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    def filter(predicate: Callable[[T, U], Bool]) -> Map[T, U]: ...

    # Transforms values in insertion order, retaining original keys.
    # Returns owned storage with copied keys and owned results.
    def map[W](transform: Callable[[T, U], W]) -> Map[T, W]: ...

    # Transforms keys in insertion order, copying values.
    # Equal outputs keep the first key/position and the last input value.
    def map_keys[W: Hashable](transform: Callable[[T, U], W]) -> Map[W, U]: ...

    # Returns the stored value or an eagerly evaluated fallback without inserting.
    def get_or(key: T, fallback: U) -> U: ...

    # Reduces entries in insertion order, starting with initial.
    def fold[A](initial: A, step: Callable[[A, T, U], A]) -> A: ...

    # Reduces entries in reverse insertion order, starting with initial.
    def fold_right[A](initial: A, step: Callable[[A, T, U], A]) -> A: ...

    # Returns the first matching entry as an owned record containing copies of the key and value.
    def find(predicate: Callable[[T, U], Bool]) -> Optional[MapEntry[T, U]]: ...

    # Searches from the end, stopping at the last matching entry.
    # Returns a fresh entry record containing copies of its key and value.
    def find_last(predicate: Callable[[T, U], Bool]) -> Optional[MapEntry[T, U]]: ...

    # Stops at the first matching entry; empty maps return False.
    def any(predicate: Callable[[T, U], Bool]) -> Bool: ...

    # Stops at the first nonmatching entry; empty maps return True.
    def all(predicate: Callable[[T, U], Bool]) -> Bool: ...

    # Inserts a default only when the key is absent.
    # The supplied value evaluates normally even when the key already exists.
    var def add_default(key: T, value: U) -> Unit: ...

    # Creates and inserts a default only when the key is absent.
    # Calls create(key:) once for absence; an existing key leaves its value and position unchanged.
    var def add_default_from(key: T, create: Callable[[T], U]) -> Unit: ...

    # Removes every entry in place.
    var def clear() -> Unit: ...

    # Returns a new list of the keys in insertion order.
    def keys() -> List[T]: ...

    # Returns a new list of the values in insertion order.
    def values() -> List[U]: ...

    # Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.
    def entries() -> List[MapEntry[T, U]]: ...

    # Copies every entry of `other` into this map in place.
    # Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.
    var def merge(other: Map[T, U]) -> Unit: ...

    # Calls operation(key:, value:) sequentially over the receiver in insertion order.
    def for_each(operation: Callable[[T, U], Unit]) -> Unit: ...

    # Reports whether an equal key is present, using the key type's Hashable implementation.
    def contains(key: T) -> Bool: ...

    # Returns the value stored for an equal key, or none when the key is absent.
    def get(key: T) -> ref Optional[U]: ...

    # Returns the number of entries.
    def length() -> Int: ...

    # Inserts or replaces a value; replacement keeps the original key and insertion position.
    var def add(key: T, value: U) -> Unit: ...

    # Removes an equal key in place; remaining entries retain insertion order.
    # An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.
    var def remove(key: T) -> Unit: ...

# One key-value pair returned by `Map.entries`.
export type MapEntry[T: Hashable, U]:
    # The lookup identity of the pair; unique within its map under Hashable equality.
    key: T
    # The payload stored for `key`; accessing this field can borrow from the entry.
    value: U

# A mutable collection of unique values using explicit `Hashable` value semantics.
export type Set[T: Hashable]: ...

impl Set[T]:
    # Copies elements deeply into independent storage, retaining insertion order.
    def clone() -> Set[T]: ...

    # Reports whether this set has no elements.
    def is_empty() -> Bool: ...

    # Copies matching elements and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    def filter(predicate: Callable[[T], Bool]) -> Set[T]: ...

    # Transforms elements into a fresh set, retaining the first equal result.
    def map[U: Hashable](transform: Callable[[T], U]) -> Set[U]: ...

    # Reduces elements in insertion order, starting with initial.
    def fold[A](initial: A, step: Callable[[A, T], A]) -> A: ...

    # Reduces elements in reverse insertion order, starting with initial.
    def fold_right[A](initial: A, step: Callable[[A, T], A]) -> A: ...

    # Returns the original first matching element, or none.
    def find(predicate: Callable[[T], Bool]) -> Optional[T]: ...

    # Searches from the end, returning the original last matching element.
    def find_last(predicate: Callable[[T], Bool]) -> Optional[T]: ...

    # Stops at the first matching element; empty sets return False.
    def any(predicate: Callable[[T], Bool]) -> Bool: ...

    # Stops at the first nonmatching element; empty sets return True.
    def all(predicate: Callable[[T], Bool]) -> Bool: ...

    # Returns a new set with receiver values followed by right-only values in insertion order.
    def union(other: Set[T]) -> Set[T]: ...

    # Returns a new set of receiver values also in right, preserving receiver insertion order.
    def intersection(other: Set[T]) -> Set[T]: ...

    # Returns a new set of receiver values absent from right, preserving receiver insertion order.
    def difference(other: Set[T]) -> Set[T]: ...

    # Returns a new set of values in exactly one operand; leaves both operands unchanged.
    def symmetric_difference(other: Set[T]) -> Set[T]: ...

    # Tests whether every receiver value also occurs in right.
    def is_subset_of(other: Set[T]) -> Bool: ...

    # Tests whether every right value also occurs in the receiver.
    def is_superset_of(other: Set[T]) -> Bool: ...

    # Tests whether the operands have no common values.
    def is_disjoint_from(other: Set[T]) -> Bool: ...

    # Removes all values in place.
    var def clear() -> Unit: ...

    # Returns an owned list containing copies of values in insertion order.
    def values() -> List[T]: ...

    # Calls operation(value:) sequentially over the receiver in insertion order.
    def for_each(operation: Callable[[T], Unit]) -> Unit: ...

    # Reports whether an equal value is present, using the element's Hashable implementation.
    def contains(value: T) -> Bool: ...

    # Returns the number of distinct values currently stored.
    def length() -> Int: ...

    # Adds a value in place; an equal value retains its original payload and position.
    var def add(value: T) -> Unit: ...

    # Removes an equal value in place; an absent value leaves it unchanged.
    var def remove(value: T) -> Unit: ...

# Two values of possibly different types, as produced by `List.zip`.
export type Pair[A, B]:
    # The value taken from the receiver list.
    first: A
    # The value taken from the argument list.
    second: B

# The two lists `List.partition` produces: elements the predicate accepted and the rest, each in original order.
export type Partition[T]:
    # Elements for which the predicate was True, in original order.
    matching: List[T]
    # Elements for which the predicate was False, in original order.
    rest: List[T]

# One list index and its corresponding value.
export type ListEntry[T]:
    # Zero-based position of the element in the list that produced this entry.
    index: Int
    # The element found at `index`.
    value: T

# Creates a list containing `value` repeated `count` times.
export def filled[T](
    value: T,
    count: Int,
    max_items: Optional[Int] = none
) -> Result[List[T], CollectionError]: ...

# Creates the integers from `start` up to but excluding `end`, counting by one. The list is empty when `end <= start`. `start..end` is the same call without the import. `for index in 0..count:` and `for index in range(0, count):` run as counter loops without allocating the list. As a stored list, more than about 268 million items is a fault; use `range_by` to bound the size with an error value.
export def range(start: Int, end: Int) -> List[Int]: ...

# Creates integers from `start` up to but excluding `end` using a nonzero `step`; a negative step counts down. Returns `InvalidInput` for a zero step and `LimitExceeded` when the list would exceed `max_items`.
export def range_by(
    start: Int,
    end: Int,
    step: Int,
    max_items: Optional[Int] = none
) -> Result[List[Int], CollectionError]: ...

# Builds a map from entries. Later entries replace earlier values for duplicate keys.
export def map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]: ...

impl Error for CollectionError:
    # Returns the fixed diagnostic `collection: <reason>`, such as `collection: limit exceeded`, without echoing values.
    def message() -> String: ...

# Appends values efficiently before freezing them into a list.
export type ListBuilder[T]: ...

impl ListBuilder[T]:
    # Adds `value` to the end of the mutable builder and returns Unit.
    # A frozen builder faults.
    def append(value: T) -> Unit: ...

    # Seals the builder and returns the accumulated list without copying it.
    # Later `append` calls fault.
    def build() -> List[T]: ...

# Adds entries efficiently before freezing them into a map.
export type MapBuilder[T: Hashable, U]: ...

impl MapBuilder[T, U]:
    # Seals the builder and returns the accumulated map without copying it.
    # Later `add` calls fault.
    def build() -> Map[T, U]: ...

    # Inserts or replaces an entry in the mutable builder; returns Unit like all builder mutations.
    # Replacement retains the original key and insertion position; a sealed builder faults.
    def add(key: T, value: U) -> Unit: ...

# Adds unique values efficiently before freezing them into a set.
export type SetBuilder[T: Hashable]: ...

impl SetBuilder[T]:
    # Seals the builder and returns the accumulated set without copying it.
    # Later `add` calls fault.
    def build() -> Set[T]: ...

    # Adds a value to the mutable builder; returns Unit like all builder mutations.
    # Equal values retain the first payload and position; a sealed builder faults.
    def add(value: T) -> Unit: ...

# Concatenates the inner lists in order into one new list (JavaScript `Array.prototype.flat`).
export def flatten[T](lists: List[List[T]]) -> List[T]: ...

# List operations written in Manuscript. Each interface gathers the operations that need a bound on the element type;
# a List[T] has them only when T meets the bound. They apply wherever List is used, without an import.
interface ListIntSum:
    def sum() -> Int

impl ListIntSum for List[Int]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    def sum() -> Int:
        var total: Int = 0
        for x in self:
            total += x
        return total

interface ListFloatSum:
    def sum() -> Float

impl ListFloatSum for List[Float]:
    # Adds the elements left to right with `+` in binary64 arithmetic; an empty list sums to 0.0.
    # Example: `[1.5, 2.5].sum()` is `4.0`.
    def sum() -> Float:
        var total: Float = 0.0
        for x in self:
            total += x
        return total

interface ListInt8Sum:
    def sum() -> Int8

impl ListInt8Sum for List[Int8]:
    # Adds the elements left to right with `+`, so Int8 overflow faults; an empty list sums to 0.
    def sum() -> Int8:
        var total: Int8 = 0
        for x in self:
            total += x
        return total

interface ListInt16Sum:
    def sum() -> Int16

impl ListInt16Sum for List[Int16]:
    # Adds the elements left to right with `+`, so Int16 overflow faults; an empty list sums to 0.
    def sum() -> Int16:
        var total: Int16 = 0
        for x in self:
            total += x
        return total

interface ListInt32Sum:
    def sum() -> Int32

impl ListInt32Sum for List[Int32]:
    # Adds the elements left to right with `+`, so Int32 overflow faults; an empty list sums to 0.
    def sum() -> Int32:
        var total: Int32 = 0
        for x in self:
            total += x
        return total

interface ListFloat32Sum:
    def sum() -> Float32

impl ListFloat32Sum for List[Float32]:
    # Adds the elements left to right with `+` in binary32 arithmetic; an empty list sums to 0.0.
    def sum() -> Float32:
        var total: Float32 = 0.0
        for x in self:
            total += x
        return total

interface ListOrder[T: Comparable]:
    def sorted() -> List[T]
    var def sort() -> Unit

impl ListOrder[T] for List[T]:
    # Returns a new list in ascending natural order; the receiver is unchanged. The sort is stable: equal elements keep their order.
    # Float orders NaN above every other value.
    # Example: `[3, 1, 2].sorted()` is `[1, 2, 3]`.
    def sorted() -> List[T]:
        return self.sorted(lambda a, b: a.compare(b))

    # Sorts the list in place, stably, in the same order as `sorted()`.
    # Example: `var xs = [3, 1, 2]` then `xs.sort()` leaves `[1, 2, 3]`.
    var def sort() -> Unit:
        self.sort(lambda a, b: a.compare(b))

interface ListExtremes[T: Comparable & Clonable]:
    def min() -> Optional[T]
    def max() -> Optional[T]

impl ListExtremes[T] for List[T]:
    # Returns a copy of the least element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].min()` is `some(1)`; `List[Int]().min()` is `none`.
    def min() -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self[i].compare(self[at]) < 0:
                at = i
        return some(self[at].clone())

    # Returns a copy of the greatest element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].max()` is `some(3)`.
    def max() -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self[i].compare(self[at]) > 0:
                at = i
        return some(self[at].clone())

interface ListKeyedExtremes[T: Clonable]:
    def max_by[K: Comparable](key: Callable[[T], K]) -> Optional[T]
    def min_by[K: Comparable](key: Callable[[T], K]) -> Optional[T]

impl ListKeyedExtremes[T] for List[T]:
    # Returns the first element whose `key` is greatest, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
    # Returns a copy of the element, like `find`.
    # Example: `["bb", "a", "ccc"].max_by(lambda (w: String) -> Int: w.length())` is `some("ccc")`.
    def max_by[K: Comparable](key: Callable[[T], K]) -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        var best = key(self[0])

        for i in 1..self.length():
            let k = key(self[i])

            if k.compare(best) > 0:
                at = i
                best = k

        return some(self[at].clone())

    # Returns the first element whose `key` is least, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
    # Returns a copy of the element, like `find`.
    # Example: `["bb", "a", "ccc"].min_by(lambda (w: String) -> Int: w.length())` is `some("a")`.
    def min_by[K: Comparable](key: Callable[[T], K]) -> Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        var best = key(self[0])

        for i in 1..self.length():
            let k = key(self[i])

            if k.compare(best) < 0:
                at = i
                best = k

        return some(self[at].clone())
