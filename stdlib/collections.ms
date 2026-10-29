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
    fn clone() List[T]: ...

    # Returns an element; negative indexes are relative to the end. An out-of-range index returns `default`; pass one for indexes that may miss, or use `first()` and `last()`.
    # Without a default, an out-of-range index raises a fault, as `xs[i]` does.
    fn get(index: Int, default: Optional[T] = none) ref T: ...

    # Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns False.
    fn contains(value: T) Bool: ...

    # Returns the first equal element's zero-based index, or none; elements require Equal.
    fn index_of(value: T) Optional[Int]: ...

    # Returns the last equal element's zero-based index, or none; elements require Equal.
    fn last_index_of(value: T) Optional[Int]: ...

    # Returns the first element, or none when the list is empty.
    fn first() ref Optional[T]: ...

    # Returns the last element, or none when the list is empty.
    fn last() ref Optional[T]: ...

    # Reports whether the list has no elements.
    fn is_empty() Bool: ...

    # Inserts `value` at index 0 in place, shifting existing elements one position later.
    var fn prepend(value: T) Unit: ...

    # Inserts value before index in place; negative indexes count from the end.
    # Requires -length() <= index <= length(); index length() appends, and invalid indexes fault.
    var fn insert(index: Int, value: T) Unit: ...

    # Removes and returns the last element in place, or none for an empty list.
    var fn pop() Optional[T]: ...

    # Replaces an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    var fn set(index: Int, value: T) Unit: ...

    # Stores value at index in place and returns the element that was there, moving both without copying.
    # Negative indexes count from the end; invalid indexes fault.
    var fn replace(index: Int, value: T) T: ...

    # Exchanges the elements at i and j in place without copying them; equal indexes change nothing.
    # Negative indexes count from the end; invalid indexes fault.
    var fn swap(i: Int, j: Int) Unit: ...

    # Removes an element in place; negative indexes count from the end.
    # Invalid indexes fault.
    # Shifts the suffix without clearing prior values retained in spare backing capacity.
    var fn remove(index: Int) Unit: ...

    # Returns a new owned List containing copies of the elements in [start, end).
    # Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    fn slice(start: Int, end: Int) Result[List[T], CollectionError]: ...

    # Copies the first min(count, length) elements into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn take(count: Int) List[T]: ...

    # Copies the remainder after min(count, length) into fresh owned List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn drop(count: Int) List[T]: ...

    # Pairs elements by position into fresh `Pair` records, stopping at the shorter list; both lists are unchanged.
    fn zip[U](other: List[U]) List[Pair[T, U]]: ...

    # Splits the list into consecutive copies of `size` elements; the last chunk may be shorter, and an empty list gives an empty list.
    # A `size` of zero or less is a programming fault.
    fn chunks(size: Int) List[List[T]]: ...

    # Returns each run of `size` consecutive elements as an overlapping copy, in order; a list shorter than `size` gives an empty list.
    # A `size` of zero or less is a programming fault. Windows are copies: `slice` and `take` do not borrow today.
    fn windows(size: Int) List[List[T]]: ...

    # Calls `predicate` once per element in order and splits the elements into those that matched and the rest, each keeping the original order.
    fn partition(predicate: fn(T) Bool) Partition[T]: ...

    # Reverses this list in place.
    var fn reverse() Unit: ...

    # Returns an independent reversed copy, including nested values.
    fn reversed() List[T]: ...

    # Returns a new list ordered by `compare`; the receiver is unchanged. The sort is stable: equal elements keep their order.
    # A negative, zero or positive result puts the first argument before, level with or after the second. Comparable elements also have `sorted()` without a comparator.
    # Example: `names.sorted(lambda a, b: a.length() - b.length())` orders by length.
    fn sorted(compare: fn(T, T) Int) List[T]: ...

    # Sorts the list in place, stably, in the order of `compare`, as `sorted` does. Comparable elements also have `sort()` without a comparator.
    # Example: `var xs = [3, 1, 2]` then `xs.sort(lambda a, b: b - a)` leaves `[3, 2, 1]`.
    var fn sort(compare: fn(T, T) Int) Unit: ...

    # Keeps matching values in their original order.
    fn filter(predicate: fn(T) Bool) List[T]: ...

    # Returns the first element for which `predicate` is True, or none; later elements are not tested after a match.
    fn find(predicate: fn(T) Bool) Optional[T]: ...

    # Searches from the end and returns the last element for which `predicate` is True, or none.
    fn find_last(predicate: fn(T) Bool) Optional[T]: ...

    # Returns the zero-based index of the first element for which `predicate` is True, or none.
    fn find_index(predicate: fn(T) Bool) Optional[Int]: ...

    # Searches from the end and returns the last matching zero-based index, or none.
    fn find_last_index(predicate: fn(T) Bool) Optional[Int]: ...

    # Counts values satisfying the predicate, calling it once per element in order.
    fn count(predicate: fn(T) Bool) Int: ...

    # Returns a new owned List keeping a copy of each first equal element in order; elements require Equal.
    fn distinct() List[T]: ...

    # Returns True when at least one value satisfies the predicate.
    fn any(predicate: fn(T) Bool) Bool: ...

    # Returns True when every value satisfies the predicate; empty lists return True.
    fn all(predicate: fn(T) Bool) Bool: ...

    # Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.
    fn for_each(operation: fn(T) Unit) Unit: ...

    # Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
    # Keys appear in first-seen order and each group keeps the original element order.
    fn group_by[K: Hashable](key: fn(T) K) Map[K, List[T]]: ...

    # Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.
    fn map[U](transform: fn(T) U) List[U]: ...

    # Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.
    fn flat_map[U](transform: fn(T) List[U]) List[U]: ...

    # Reduces values from left to right, starting with `initial`.
    fn fold[A](initial: A, step: fn(A, T) A) A: ...

    # Reduces values from right to left, starting with `initial`.
    fn fold_right[A](initial: A, step: fn(A, T) A) A: ...

    # Replaces delete_count elements starting at start in place, consuming the replacement list and returning Unit.
    # Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
    # Removed elements are dropped; replacement elements move into the receiver. Overlapping receiver and replacement arguments are rejected.
    var fn splice(start: Int, delete_count: Int, replacement: List[T]) Unit: ...

    # Sets elements in [start, end) to `value` in place.
    # Bounds must satisfy 0 <= start <= end <= length(); negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.
    var fn fill(value: T, start: Int, end: Int) Unit: ...

    # Copies the elements in [start, end) to begin at index `target`, in place.
    # The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length() and a target must be within 0 through length(); otherwise the call faults.
    var fn copy_within(target: Int, start: Int, end: Int) Unit: ...

    # Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.
    fn to_set() Set[T]: ...

    # Returns a new list of the zero-based indexes 0 through length() - 1.
    fn keys() List[Int]: ...

    # Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.
    fn entries() List[ListEntry[T]]: ...

    # Concatenates the strings (or the decimal text of the integers) with `separator` between neighbors; an empty list returns an empty string.
    # Available only on List[String] and List[Int].
    fn join(separator: String) String: ...

    # Adds `value` at the end in place.
    var fn append(value: T) Unit: ...

    # Returns a new list holding this list's elements followed by `other`; neither operand is changed.
    fn concat(other: List[T]) List[T]: ...

    # Returns the number of elements.
    fn length() Int: ...

# A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export type Map[T: Hashable, U]: ...

impl Map[T, U]:
    # Returns a deep copy with independent map and nested value storage.
    fn clone() Map[T, U]: ...

    # Reports whether this map has no entries.
    fn is_empty() Bool: ...

    # Copies matching entries and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    fn filter(predicate: fn(T, U) Bool) Map[T, U]: ...

    # Transforms values in insertion order, retaining original keys.
    # Returns owned storage with copied keys and owned results.
    fn map[W](transform: fn(T, U) W) Map[T, W]: ...

    # Transforms keys in insertion order, copying values.
    # Equal outputs keep the first key/position and the last input value.
    fn map_keys[W: Hashable](transform: fn(T, U) W) Map[W, U]: ...

    # Returns the stored value or an eagerly evaluated fallback without inserting.
    fn get_or(key: T, fallback: U) U: ...

    # Reduces entries in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(A, T, U) A) A: ...

    # Reduces entries in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(A, T, U) A) A: ...

    # Returns the first matching entry as an owned record containing copies of the key and value.
    fn find(predicate: fn(T, U) Bool) Optional[MapEntry[T, U]]: ...

    # Searches from the end, stopping at the last matching entry.
    # Returns a fresh entry record containing copies of its key and value.
    fn find_last(predicate: fn(T, U) Bool) Optional[MapEntry[T, U]]: ...

    # Stops at the first matching entry; empty maps return False.
    fn any(predicate: fn(T, U) Bool) Bool: ...

    # Stops at the first nonmatching entry; empty maps return True.
    fn all(predicate: fn(T, U) Bool) Bool: ...

    # Inserts a default only when the key is absent.
    # The supplied value evaluates normally even when the key already exists.
    var fn add_default(key: T, value: U) Unit: ...

    # Creates and inserts a default only when the key is absent.
    # Calls create(key:) once for absence; an existing key leaves its value and position unchanged.
    var fn add_default_from(key: T, create: fn(T) U) Unit: ...

    # Removes every entry in place.
    var fn clear() Unit: ...

    # Returns a new list of the keys in insertion order.
    fn keys() List[T]: ...

    # Returns a new list of the values in insertion order.
    fn values() List[U]: ...

    # Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.
    fn entries() List[MapEntry[T, U]]: ...

    # Copies every entry of `other` into this map in place.
    # Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.
    var fn merge(other: Map[T, U]) Unit: ...

    # Calls operation(key:, value:) sequentially over the receiver in insertion order.
    fn for_each(operation: fn(T, U) Unit) Unit: ...

    # Reports whether an equal key is present, using the key type's Hashable implementation.
    fn contains(key: T) Bool: ...

    # Returns the value stored for an equal key, or none when the key is absent.
    fn get(key: T) ref Optional[U]: ...

    # Returns the number of entries.
    fn length() Int: ...

    # Inserts or replaces a value; replacement keeps the original key and insertion position.
    var fn add(key: T, value: U) Unit: ...

    # Removes an equal key in place; remaining entries retain insertion order.
    # An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.
    var fn remove(key: T) Unit: ...

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
    fn clone() Set[T]: ...

    # Reports whether this set has no elements.
    fn is_empty() Bool: ...

    # Copies matching elements and their nested values in insertion order.
    # Callbacks borrow the receiver; mutating it during traversal is rejected.
    fn filter(predicate: fn(T) Bool) Set[T]: ...

    # Transforms elements into a fresh set, retaining the first equal result.
    fn map[U: Hashable](transform: fn(T) U) Set[U]: ...

    # Reduces elements in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(A, T) A) A: ...

    # Reduces elements in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(A, T) A) A: ...

    # Returns the original first matching element, or none.
    fn find(predicate: fn(T) Bool) Optional[T]: ...

    # Searches from the end, returning the original last matching element.
    fn find_last(predicate: fn(T) Bool) Optional[T]: ...

    # Stops at the first matching element; empty sets return False.
    fn any(predicate: fn(T) Bool) Bool: ...

    # Stops at the first nonmatching element; empty sets return True.
    fn all(predicate: fn(T) Bool) Bool: ...

    # Returns a new set with receiver values followed by right-only values in insertion order.
    fn union(other: Set[T]) Set[T]: ...

    # Returns a new set of receiver values also in right, preserving receiver insertion order.
    fn intersection(other: Set[T]) Set[T]: ...

    # Returns a new set of receiver values absent from right, preserving receiver insertion order.
    fn difference(other: Set[T]) Set[T]: ...

    # Returns a new set of values in exactly one operand; leaves both operands unchanged.
    fn symmetric_difference(other: Set[T]) Set[T]: ...

    # Tests whether every receiver value also occurs in right.
    fn is_subset_of(other: Set[T]) Bool: ...

    # Tests whether every right value also occurs in the receiver.
    fn is_superset_of(other: Set[T]) Bool: ...

    # Tests whether the operands have no common values.
    fn is_disjoint_from(other: Set[T]) Bool: ...

    # Removes all values in place.
    var fn clear() Unit: ...

    # Returns an owned list containing copies of values in insertion order.
    fn values() List[T]: ...

    # Calls operation(value:) sequentially over the receiver in insertion order.
    fn for_each(operation: fn(T) Unit) Unit: ...

    # Reports whether an equal value is present, using the element's Hashable implementation.
    fn contains(value: T) Bool: ...

    # Returns the number of distinct values currently stored.
    fn length() Int: ...

    # Adds a value in place; an equal value retains its original payload and position.
    var fn add(value: T) Unit: ...

    # Removes an equal value in place; an absent value leaves it unchanged.
    var fn remove(value: T) Unit: ...

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
export fn filled[T](
    value: T,
    count: Int,
    max_items: Optional[Int] = none
) Result[List[T], CollectionError]: ...

# Creates the integers from `start` up to but excluding `end`, counting by one. Written `start..end`; the name `range` is not importable. The list is empty when `end <= start`. `for index in 0..count:` runs as a counter loop without allocating the list. As a stored list, more than about 268 million items is a fault; use `range_by` to bound the size with an error value.
fn range(start: Int, end: Int) List[Int]: ...

# Creates integers from `start` up to but excluding `end` using a nonzero `step`; a negative step counts down. Returns `InvalidInput` for a zero step and `LimitExceeded` when the list would exceed `max_items`.
export fn range_by(
    start: Int,
    end: Int,
    step: Int,
    max_items: Optional[Int] = none
) Result[List[Int], CollectionError]: ...

# Builds a map from entries. Later entries replace earlier values for duplicate keys.
export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) Map[K, V]: ...

impl Error for CollectionError:
    # Returns the fixed diagnostic `collection: <reason>`, such as `collection: limit exceeded`, without echoing values.
    fn message() String: ...

# Appends values efficiently before freezing them into a list.
export type ListBuilder[T]: ...

impl ListBuilder[T]:
    # Adds `value` to the end of the mutable builder and returns Unit.
    # A frozen builder faults.
    fn append(value: T) Unit: ...

    # Seals the builder and returns the accumulated list without copying it.
    # Later `append` calls fault.
    fn build() List[T]: ...

# Adds entries efficiently before freezing them into a map.
export type MapBuilder[T: Hashable, U]: ...

impl MapBuilder[T, U]:
    # Seals the builder and returns the accumulated map without copying it.
    # Later `add` calls fault.
    fn build() Map[T, U]: ...

    # Inserts or replaces an entry in the mutable builder; returns Unit like all builder mutations.
    # Replacement retains the original key and insertion position; a sealed builder faults.
    fn add(key: T, value: U) Unit: ...

# Adds unique values efficiently before freezing them into a set.
export type SetBuilder[T: Hashable]: ...

impl SetBuilder[T]:
    # Seals the builder and returns the accumulated set without copying it.
    # Later `add` calls fault.
    fn build() Set[T]: ...

    # Adds a value to the mutable builder; returns Unit like all builder mutations.
    # Equal values retain the first payload and position; a sealed builder faults.
    fn add(value: T) Unit: ...

# Concatenates the inner lists in order into one new list (JavaScript `Array.prototype.flat`).
export fn flatten[T](lists: List[List[T]]) List[T]: ...

# List operations written in Manuscript. Each interface gathers the operations that need a bound on the element type;
# a List[T] has them only when T meets the bound. They apply wherever List is used, without an import.
interface ListIntSum:
    fn sum() Int

impl ListIntSum for List[Int]:
    # Adds the elements left to right with `+`, so integer overflow faults; an empty list sums to 0.
    # Example: `[1, 2, 3].sum()` is `6`.
    fn sum() Int:
        var total: Int = 0
        for x in self:
            total += x
        return total

interface ListFloatSum:
    fn sum() Float

impl ListFloatSum for List[Float]:
    # Adds the elements left to right with `+` in binary64 arithmetic; an empty list sums to 0.0.
    # Example: `[1.5, 2.5].sum()` is `4.0`.
    fn sum() Float:
        var total: Float = 0.0
        for x in self:
            total += x
        return total

interface ListInt8Sum:
    fn sum() Int8

impl ListInt8Sum for List[Int8]:
    # Adds the elements left to right with `+`, so Int8 overflow faults; an empty list sums to 0.
    fn sum() Int8:
        var total: Int8 = 0
        for x in self:
            total += x
        return total

interface ListInt16Sum:
    fn sum() Int16

impl ListInt16Sum for List[Int16]:
    # Adds the elements left to right with `+`, so Int16 overflow faults; an empty list sums to 0.
    fn sum() Int16:
        var total: Int16 = 0
        for x in self:
            total += x
        return total

interface ListInt32Sum:
    fn sum() Int32

impl ListInt32Sum for List[Int32]:
    # Adds the elements left to right with `+`, so Int32 overflow faults; an empty list sums to 0.
    fn sum() Int32:
        var total: Int32 = 0
        for x in self:
            total += x
        return total

interface ListUInt8Sum:
    fn sum() UInt8

impl ListUInt8Sum for List[UInt8]:
    # Adds the elements left to right with `+`, so UInt8 overflow faults; an empty list sums to 0.
    fn sum() UInt8:
        var total: UInt8 = 0
        for x in self:
            total += x
        return total

interface ListUInt16Sum:
    fn sum() UInt16

impl ListUInt16Sum for List[UInt16]:
    # Adds the elements left to right with `+`, so UInt16 overflow faults; an empty list sums to 0.
    fn sum() UInt16:
        var total: UInt16 = 0
        for x in self:
            total += x
        return total

interface ListUInt32Sum:
    fn sum() UInt32

impl ListUInt32Sum for List[UInt32]:
    # Adds the elements left to right with `+`, so UInt32 overflow faults; an empty list sums to 0.
    fn sum() UInt32:
        var total: UInt32 = 0
        for x in self:
            total += x
        return total

interface ListFloat32Sum:
    fn sum() Float32

impl ListFloat32Sum for List[Float32]:
    # Adds the elements left to right with `+` in binary32 arithmetic; an empty list sums to 0.0.
    fn sum() Float32:
        var total: Float32 = 0.0
        for x in self:
            total += x
        return total

interface ListOrder[T: Comparable]:
    fn sorted() List[T]
    var fn sort() Unit

impl ListOrder[T] for List[T]:
    # Returns a new list in ascending natural order; the receiver is unchanged. The sort is stable: equal elements keep their order.
    # Float orders NaN above every other value.
    # Example: `[3, 1, 2].sorted()` is `[1, 2, 3]`.
    fn sorted() List[T]:
        return self.sorted(fn a, b: a.compare(b))

    # Sorts the list in place, stably, in the same order as `sorted()`.
    # Example: `var xs = [3, 1, 2]` then `xs.sort()` leaves `[1, 2, 3]`.
    var fn sort() Unit:
        self.sort(fn a, b: a.compare(b))

interface ListExtremes[T: Comparable & Clonable]:
    fn min() Optional[T]
    fn max() Optional[T]

impl ListExtremes[T] for List[T]:
    # Returns a copy of the least element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].min()` is `some(1)`; `List[Int]().min()` is `none`.
    fn min() Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self[i].compare(self[at]) < 0:
                at = i
        return self[at].clone()

    # Returns a copy of the greatest element, or none for an empty list; the first of equal elements wins.
    # Example: `[3, 1, 2].max()` is `some(3)`.
    fn max() Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        for i in 1..self.length():
            if self[i].compare(self[at]) > 0:
                at = i
        return self[at].clone()

interface ListKeyedExtremes[T: Clonable]:
    fn max_by[K: Comparable](key: fn(T) K) Optional[T]
    fn min_by[K: Comparable](key: fn(T) K) Optional[T]

impl ListKeyedExtremes[T] for List[T]:
    # Returns the first element whose `key` is greatest, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
    # Returns a copy of the element, like `find`.
    # Example: `["bb", "a", "ccc"].max_by(lambda (w: String) -> Int: w.length())` is `some("ccc")`.
    fn max_by[K: Comparable](key: fn(T) K) Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        var best = key(self[0])

        for i in 1..self.length():
            let k = key(self[i])

            if k.compare(best) > 0:
                at = i
                best = k

        return self[at].clone()

    # Returns the first element whose `key` is least, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
    # Returns a copy of the element, like `find`.
    # Example: `["bb", "a", "ccc"].min_by(lambda (w: String) -> Int: w.length())` is `some("a")`.
    fn min_by[K: Comparable](key: fn(T) K) Optional[T]:
        if self.length() == 0:
            return none

        var at = 0
        var best = key(self[0])

        for i in 1..self.length():
            let k = key(self[i])

            if k.compare(best) < 0:
                at = i
                best = k

        return self[at].clone()

# Map operations written in Manuscript. A Map[T, U] has them only when T can be cloned for storage.
interface MapUpdate[T: Hashable & Clonable, U]:
    var fn update(key: T, initial: U, change: fn(U) U) Unit

impl MapUpdate[T, U] for Map[T, U]:
    # Stores `change` applied to the value for `key`, or to `initial` when the key is absent.
    # Example: `counts.update(word, 0, lambda n: n + 1)` counts occurrences.
    var fn update(key: T, initial: U, change: fn(U) U) Unit:
        self.add(key.clone(), change(self.get_or(key, initial)))

import Closeable from "@std/core.ms"

# Closing the resources a map holds. The compiler calls this when a map of resources goes out of scope; the values close newest entry first.
interface MapCloseValues[U: Closeable]:
    var fn close_values() Unit

impl MapCloseValues[U] for Map[T, U]:
    # Closes every value in place, last inserted first. The entries stay in the map.
    var fn close_values() Unit:
        let keys = self.keys()
        var i = keys.length() - 1

        while i >= 0:
            if var value = self.get(keys[i]):
                value.close()
            i -= 1
