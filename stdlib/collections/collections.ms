/*
An ordered mutable collection with indexing, iteration, and transformations.
Start with a literal such as `["docs", "release"]`; use `var` when you want to append, remove, or replace items.
Lists are owned values; clone makes a deep copy and accessors can borrow elements.
`List[T]()` creates an empty list; `List[T](reserve: n)` also preallocates room for `n` items without changing the length. A negative `n` reserves nothing.
*/
export type List[T]:
	// Constructor-only capacity hint in items: room for this many elements is allocated
	// up front. The list starts empty; none or a negative value reserves nothing.
	reserve: Int?

// Returns an element; negative indexes are relative to the end. An out-of-range
// index returns `default`; pass one for indexes that may miss, or use `first()` and
// `last()`. Without a default, an out-of-range index raises a fault, as `xs[i]`
// does.
fn List[T].get(index: Int, default: T?) T: ...

// Returns the first element, or none when the list is empty.
fn List[T].first() T?:
	if self.is_empty(): return none
	return self.get(0)

// Returns the last element, or none when the list is empty.
fn List[T].last() T?:
	if self.is_empty(): return none
	return self.get(-1)

// Reports whether the list has no elements.
fn List[T].is_empty() Bool: ...

// Inserts `value` at index 0 in place, shifting existing elements one position
// later.
fn var List[T].prepend(value: T) Unit: ...

// Inserts value before index in place; negative indexes count from the end.
// Requires -length() <= index <= length(); index length() appends, and invalid
// indexes fault.
fn var List[T].insert(index: Int, value: T) Unit: ...

// Removes and returns the last element in place, or none for an empty list.
fn var List[T].pop() T?: ...

// Replaces an element in place; negative indexes count from the end.
// Invalid indexes fault.
fn var List[T].set(index: Int, value: T) Unit: ...

// Stores value at index in place and returns the element that was there, moving
// both without copying. Negative indexes count from the end; invalid indexes fault.
fn var List[T].replace(index: Int, value: T) T: ...

// Exchanges the elements at i and j in place without copying them; equal indexes
// change nothing. Negative indexes count from the end; invalid indexes fault.
fn var List[T].swap(i: Int, j: Int) Unit: ...

/*
Removes an element in place; negative indexes count from the end.
Invalid indexes fault.
Shifts the suffix without clearing prior values retained in spare backing capacity.
*/
fn var List[T].remove(index: Int) Unit: ...

// Reverses this list in place.
fn var List[T].reverse() Unit: ...

// Sorts the list in place, stably, in the order of `compare`, as `sorted` does.
// Comparable elements also have `sort()` without a comparator. Example:
// `var xs = [3, 1, 2]` then `xs.sort(fn a, b: b - a)` leaves `[3, 2, 1]`.
fn var List[T].sort(compare: fn(T, T) Int) Unit: ...

// Returns the zero-based index of the first element for which `predicate` is True,
// or none.
fn List[T].find_index(predicate: fn(T) Bool) Int?: ...

// Searches from the end and returns the last matching zero-based index, or none.
fn List[T].find_last_index(predicate: fn(T) Bool) Int?: ...

// Counts values satisfying the predicate, calling it once per element in order.
fn List[T].count(predicate: fn(T) Bool) Int: ...

// Returns True when at least one value satisfies the predicate.
fn List[T].any(predicate: fn(T) Bool) Bool: ...

// Returns True when every value satisfies the predicate; empty lists return True.
fn List[T].all(predicate: fn(T) Bool) Bool: ...

// Calls operation(value:) over the initial backing slice and length; element writes
// can affect later calls, and append does not extend traversal. A callback that
// takes its parameter as `var` changes the element in place, and the receiver must
// then be `var`; a reading callback works on any list.
fn List[T].for_each(operation: fn(var T) Unit) Unit: ...

// Returns a new list holding `transform` applied to each element in order; the
// receiver is unchanged.
fn List[T].map[U](transform: fn(T) U) List[U]: ...

// Calls `transform` on each element in order and concatenates the returned lists
// into one new list; the receiver is unchanged.
fn List[T].flat_map[U](transform: fn(T) List[U]) List[U]: ...

// Reduces values from left to right, starting with `initial`.
fn List[T].fold[A](initial: A, step: fn(A, T) A) A: ...

// Reduces values from right to left, starting with `initial`.
fn List[T].fold_right[A](initial: A, step: fn(A, T) A) A: ...

/*
Replaces delete_count elements starting at start in place, consuming the replacement list and returning Unit.
Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
Removed elements are dropped; replacement elements move into the receiver. Overlapping receiver and replacement arguments are rejected.
*/
fn var List[T].splice(start: Int, delete_count: Int, replacement: List[T]) Unit: ...

// Returns a new list of the zero-based indexes 0 through length() - 1.
fn List[T].keys() List[Int]: ...

// Adds `value` at the end in place.
fn var List[T].append(value: T) Unit: ...

// Returns the number of elements.
fn List[T].length() Int: ...

// Adds the elements left to right with `+` in the element type's own arithmetic, so
// integer overflow faults and floats follow their width; an empty list sums to zero.
// Example: `[1, 2, 3].sum()` is `6`; `[1.5, 2.5].sum()` is `4.0`.
fn List[T: Numeric].sum() T:
	var total: T = 0
	for x in self:
		total += x
	return total

// Returns a deep copy with independent list and nested value storage.
fn List[T: Clonable].clone() List[T]: ...

// Returns a new owned List containing copies of the elements in [start, end).
// Negative bounds are relative to the end; bounds outside 0 <= start <= end <=
// length() return an `Error` of kind `ERANGE`.
fn List[T: Clonable].slice(start: Int, end: Int) List[T]!: ...

// Copies the first min(count, length) elements into fresh owned List storage.
// Leaves the receiver unchanged; negative count is a programming fault.
fn List[T: Clonable].take(count: Int) List[T]: ...

// Copies the remainder after min(count, length) into fresh owned List storage.
// Leaves the receiver unchanged; negative count is a programming fault.
fn List[T: Clonable].drop(count: Int) List[T]: ...

// Splits the list into consecutive copies of `size` elements; the last chunk may be
// shorter, and an empty list gives an empty list. A `size` of zero or less is a
// programming fault.
fn List[T: Clonable].chunks(size: Int) List[List[T]]: ...

// Returns each run of `size` consecutive elements as an overlapping copy, in order;
// a list shorter than `size` gives an empty list. A `size` of zero or less is a
// programming fault. Windows are copies: `slice` and `take` do not borrow today.
fn List[T: Clonable].windows(size: Int) List[List[T]]: ...

// Calls `predicate` once per element in order and splits the elements into those
// that matched and the rest, each keeping the original order.
fn List[T: Clonable].partition(predicate: fn(T) Bool) Partition[T]: ...

// Returns an independent reversed copy, including nested values.
fn List[T: Clonable].reversed() List[T]: ...

/*
Returns a new list ordered by `compare`; the receiver is unchanged. The sort is stable: equal elements keep their order.
A negative, zero or positive result puts the first argument before, level with or after the second. Comparable elements also have `sorted()` without a comparator.
Example: `names.sorted(fn a, b: a.length() - b.length())` orders by length.
*/
fn List[T: Clonable].sorted(compare: fn(T, T) Int) List[T]: ...

// Keeps matching values in their original order.
fn List[T: Clonable].filter(predicate: fn(T) Bool) List[T]: ...

// Returns the first element for which `predicate` is True, or none; later elements
// are not tested after a match.
fn List[T: Clonable].find(predicate: fn(T) Bool) T?: ...

// Searches from the end and returns the last element for which `predicate` is True,
// or none.
fn List[T: Clonable].find_last(predicate: fn(T) Bool) T?: ...

// Sets elements in [start, end) to `value` in place. Bounds must satisfy 0 <= start
// <= end <= length(); negative or larger bounds fault rather than counting from the
// end, and an empty range changes nothing.
fn var List[T: Clonable].fill(value: T, start: Int, end: Int) Unit: ...

// Copies the elements in [start, end) to begin at index `target`, in place. The
// list never grows: copying stops at the end of the list. Source bounds must
// satisfy 0 <= start <= end <= length() and a target must be within 0 through
// length(); otherwise the call faults.
fn var List[T: Clonable].copy_within(target: Int, start: Int, end: Int) Unit: ...

// Returns a new list of `ListEntry` records pairing each zero-based index with its
// element, in order.
fn List[T: Clonable].entries() List[ListEntry[T]]: ...

// Returns a new list holding this list's elements followed by `other`; neither
// operand is changed.
fn List[T: Clonable].concat(other: List[T]) List[T]: ...

// Pairs elements by position into fresh `Pair` records, stopping at the shorter
// list; both lists are unchanged.
fn List[T: Clonable].zip[U: Clonable](other: List[U]) List[Pair[T, U]]: ...

// Calls `key` once per element in order and returns a map from each distinct key to
// the elements that produced it. Keys appear in first-seen order and each group
// keeps the original element order.
fn List[T: Clonable].group_by[K: Hashable](key: fn(T) K) Map[K, List[T]]: ...

// Reports whether any element equals `value`, using the element type's Equal
// implementation; an empty list returns False.
fn List[T: Equal].contains(value: T) Bool:
	return self.any(fn x: x.equals(value))

// Returns the first equal element's zero-based index, or none; elements require
// Equal.
fn List[T: Equal].index_of(value: T) Int?:
	for i in 0..self.length():
		if self[i].equals(value): return i
	return none

// Returns the last equal element's zero-based index, or none; elements require
// Equal.
fn List[T: Equal].last_index_of(value: T) Int?:
	var i = self.length() - 1

	while i >= 0:
		if self[i].equals(value): return i

		i -= 1

	return none

// Returns a new owned List keeping a copy of each first equal element in order;
// elements require Equal and Clonable.
fn List[T: Equal & Clonable].distinct() List[T]:
	return msrt_list_distinct(self)

// Returns a new set of the distinct elements, using Hashable equality; the first of
// equal elements is kept in insertion order.
fn List[T: Hashable & Clonable].to_set() Set[T]:
	var out = Set[T]()
	for x in self:
		out.add(x.clone())
	return out

/*
Concatenates the elements' interpolation text (`"{value}"`) with `separator` between neighbors; an empty list returns an empty string.
Strings join as they are and numbers as decimal text; a record or alternative joins in its structural form.
Example: `[1, 2, 3].join(",")` is `"1,2,3"`.
*/
fn List[T].join(separator: String) String:
	var out = StringBuilder()

	for i in 0..self.length():
		if i > 0:
			out.append(separator)
		out.append("{self[i]}")

	return out.build()

/*
Returns a new list in ascending natural order; the receiver is unchanged. The sort is stable: equal elements keep their order.
Float orders NaN above every other value.
Example: `[3, 1, 2].sorted()` is `[1, 2, 3]`.
*/
fn List[T: Comparable & Clonable].sorted() List[T]:
	var out = self.clone()
	out.sort(fn a, b: a.compare(b))
	return out

// Sorts the list in place, stably, in the same order as `sorted()`.
// Example: `var xs = [3, 1, 2]` then `xs.sort()` leaves `[1, 2, 3]`.
fn var List[T: Comparable].sort() Unit:
	self.sort(fn a, b: a.compare(b))

/*
Searches in O(log n) comparisons without copying elements or changing the list.
Requires ascending natural order, as produced by `sorted()`: comparisons must form a total order, with Float NaNs last.
Sortedness is not checked; an incorrectly ordered list has an unspecified result.
Returns the first compare-equal element, or its insertion position with `found: false`; an empty list returns index 0.
Example: `[1, 3, 3, 5].binary_search(3).index` is `1`; searching for 4 gives index 3 with `found: false`.
*/
fn List[T: Comparable].binary_search(value: T) SearchResult:
	var low = 0
	var high = self.length()

	while low < high:
		middle := low + (high - low) / 2

		if self[middle].compare(value) < 0:
			low = middle + 1
		else:
			high = middle

	return SearchResult(low, low < self.length() and self[low].compare(value) == 0)

// Returns a copy of the least element, or none for an empty list; the first of
// equal elements wins. Example: `[3, 1, 2].min()` is `1`; `List[Int]().min()` is
// `none`.
fn List[T: Comparable & Clonable].min() T?:
	if self.is_empty(): return none

	var at = 0
	for i in 1..self.length():
		if self[i].compare(self[at]) < 0:
			at = i
	return self[at].clone()

// Returns a copy of the greatest element, or none for an empty list; the first of
// equal elements wins. Example: `[3, 1, 2].max()` is `3`.
fn List[T: Comparable & Clonable].max() T?:
	if self.is_empty(): return none

	var at = 0
	for i in 1..self.length():
		if self[i].compare(self[at]) > 0:
			at = i
	return self[at].clone()

/*
Returns the first element whose `key` is greatest, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
Returns a copy of the element, like `find`.
Example: `["bb", "a", "ccc"].max_by(fn w: w.length())` is `"ccc"`.
*/
fn List[T: Clonable].max_by[K: Comparable](key: fn(T) K) T?:
	if self.is_empty(): return none

	var at = 0
	var best = key(self[0])

	for i in 1..self.length():
		k := key(self[i])

		if k.compare(best) > 0:
			at = i
			best = k

	return self[at].clone()

/*
Returns the first element whose `key` is least, or none when the list is empty. `key` is called once per element in order; ties keep the earlier element.
Returns a copy of the element, like `find`.
Example: `["bb", "a", "ccc"].min_by(fn w: w.length())` is `"a"`.
*/
fn List[T: Clonable].min_by[K: Comparable](key: fn(T) K) T?:
	if self.is_empty(): return none

	var at = 0
	var best = key(self[0])

	for i in 1..self.length():
		k := key(self[i])

		if k.compare(best) < 0:
			at = i
			best = k

	return self[at].clone()

/*
Keeps only the elements for which `keep` is True, in place and in their original order; `keep` is called once per element in order.
Dropped elements are dropped (closed when they are resources), kept ones are moved, not copied.
Example: `var xs = [1, 2, 3, 4]` then `xs.retain(fn x: x % 2 == 0)` leaves `[2, 4]`.
*/
fn var List[T].retain(keep: fn(T) Bool) Unit:
	var kept = 0

	for i in 0..self.length():
		if keep(self[i]):
			self.swap(kept, i)
			kept += 1

	self.splice(kept, self.length() - kept, List[T]())

/*
Collapses each run of consecutive elements that `same` calls equal into its first element, in place.
`same(previous, next)` gets the last kept element and the candidate, so it runs once per element after the first.
Example: `var xs = [1, 1, 2, 1]` then `xs.compact_by(fn a, b: a == b)` leaves `[1, 2, 1]`.
*/
fn var List[T].compact_by(same: fn(T, T) Bool) Unit:
	if self.length() < 2: return

	var kept = 1

	for i in 1..self.length():
		if not same(self[kept - 1], self[i]):
			self.swap(kept, i)
			kept += 1

	self.splice(kept, self.length() - kept, List[T]())

/*
Moves every element `by` places toward the front in place, wrapping the first ones around to the end;
a negative `by` rotates toward the back and any magnitude is reduced modulo the length. An empty list is unchanged.
Example: `var xs = [1, 2, 3, 4]` then `xs.rotate(1)` leaves `[2, 3, 4, 1]`.
*/
fn var List[T].rotate(by: Int) Unit:
	size := self.length()
	if size < 2: return

	shift := (by % size + size) % size
	if shift == 0: return

	reverse_span(var self, 0, shift)
	reverse_span(var self, shift, size)
	reverse_span(var self, 0, size)

// Reports whether the list is already in the order `compare` defines: no element
// sorts after its successor. Empty and one-element lists are sorted.
fn List[T].is_sorted_by(compare: fn(T, T) Int) Bool:
	for i in 1..self.length():
		if compare(self[i - 1], self[i]) > 0: return false
	return true

/*
Collapses each run of consecutive equal elements into its first element, in place; elements require Equal.
Sort first to remove every duplicate; `distinct()` keeps the first of all equal elements without sorting.
Example: `var xs = [1, 1, 2, 2, 1]` then `xs.compact()` leaves `[1, 2, 1]`.
*/
fn var List[T: Equal].compact() Unit:
	self.compact_by(fn a, b: a.equals(b))

// Reports whether the list is in ascending natural order, the order `sorted()`
// produces; empty and one-element lists are. Example: `[1, 2, 2, 5].is_sorted()` is
// `true`.
fn List[T: Comparable].is_sorted() Bool:
	return self.is_sorted_by(fn a, b: a.compare(b))

// Returns a new list ordered by the natural order of `key(element)`; the receiver
// is unchanged and the sort is stable.
// `key` runs on every comparison. Example: `people.sorted_by_key(fn p: p.age)`.
fn List[T: Clonable].sorted_by_key[K: Comparable](key: fn(T) K) List[T]:
	return self.sorted(fn a, b: key(a).compare(key(b)))

// Returns a new list holding the elements `count` times over, in order; zero gives
// an empty list and a negative `count` faults. Example: `[1, 2].repeated(2)` is
// `[1, 2, 1, 2]`.
fn List[T: Clonable].repeated(count: Int) List[T]: ...

// Appends a copy of every element of `other`, in order, to this list in place;
// `other` is unchanged. The argument cannot be the receiver. Example: after
// `var xs = [1]`, `xs.extend([2, 3])` leaves `xs` as `[1, 2, 3]`.
fn var List[T: Clonable].extend(other: List[T]) Unit:
	for x in other:
		self.append(x.clone())

// A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export extern type Map[T: Hashable, U]

// Reports whether this map has no entries.
fn Map[T, U].is_empty() Bool: ...

// Transforms values in insertion order, retaining original keys.
// Returns owned storage with copied keys and owned results.
fn Map[T, U].map[W](transform: fn(T, U) W) Map[T, W]: ...

// Reduces entries in insertion order, starting with initial.
fn Map[T, U].fold[A](initial: A, step: fn(A, T, U) A) A: ...

// Reduces entries in reverse insertion order, starting with initial.
fn Map[T, U].fold_right[A](initial: A, step: fn(A, T, U) A) A: ...

// Stops at the first matching entry; empty maps return False.
fn Map[T, U].any(predicate: fn(T, U) Bool) Bool: ...

// Stops at the first nonmatching entry; empty maps return True.
fn Map[T, U].all(predicate: fn(T, U) Bool) Bool: ...

// Inserts a default only when the key is absent.
// The supplied value evaluates normally even when the key already exists.
fn var Map[T, U].add_default(key: T, value: U) Unit: ...

// Creates and inserts a default only when the key is absent. Calls create(key:)
// once for absence; an existing key leaves its value and position unchanged.
fn var Map[T, U].add_default_from(key: T, create: fn(T) U) Unit: ...

// Removes every entry in place.
fn var Map[T, U].clear() Unit: ...

// Returns a new list of the keys in insertion order.
fn Map[T, U].keys() List[T]: ...

// Calls operation(key:, value:) sequentially over the receiver in insertion order.
// A callback that takes `value` as `var` changes it in place, and the receiver must
// then be `var`.
fn Map[T, U].for_each(operation: fn(T, var U) Unit) Unit: ...

// Reports whether an equal key is present, using the key type's Hashable
// implementation.
fn Map[T, U].contains(key: T) Bool: ...

// Returns the value stored for an equal key, or none when the key is absent.
fn Map[T, U].get(key: T) U?: ...

// Returns the number of entries.
fn Map[T, U].length() Int: ...

// Inserts or replaces a value; replacement keeps the original key and insertion
// position.
fn var Map[T, U].add(key: T, value: U) Unit: ...

// Removes an equal key in place; remaining entries retain insertion order. An
// absent key leaves values and ordering unchanged; lookup uses the selected
// Equal/Hashable scope.
fn var Map[T, U].remove(key: T) Unit: ...

// Returns a deep copy with independent map and nested value storage.
fn Map[T: Hashable, U: Clonable].clone() Map[T, U]: ...

// Copies matching entries and their nested values in insertion order.
// Callbacks borrow the receiver; mutating it during traversal is rejected.
fn Map[T: Hashable, U: Clonable].filter(predicate: fn(T, U) Bool) Map[T, U]: ...

// Transforms keys in insertion order, copying values.
// Equal outputs keep the first key/position and the last input value.
fn Map[T: Hashable, U: Clonable].map_keys[W: Hashable](transform: fn(T, U) W) Map[W, U]: ...

// Returns the stored value or an eagerly evaluated fallback without inserting.
fn Map[T: Hashable, U: Clonable].get_or(key: T, fallback: U) U: ...

// Returns the first matching entry as an owned record containing copies of the key
// and value.
fn Map[T: Hashable, U: Clonable].find(predicate: fn(T, U) Bool) MapEntry[T, U]?: ...

// Searches from the end, stopping at the last matching entry.
// Returns a fresh entry record containing copies of its key and value.
fn Map[T: Hashable, U: Clonable].find_last(predicate: fn(T, U) Bool) MapEntry[T, U]?: ...

// Returns a new list of the values in insertion order.
fn Map[T: Hashable, U: Clonable].values() List[U]: ...

// Returns a new list of fresh `MapEntry` records in insertion order; keys and
// values keep their original references.
fn Map[T: Hashable, U: Clonable].entries() List[MapEntry[T, U]]: ...

// Copies every entry of `other` into this map in place. Existing keys keep their
// position and key but take the value from `other`; new keys append in `other`
// order. `other` is unchanged.
fn var Map[T: Hashable, U: Clonable].merge(other: Map[T, U]) Unit: ...

// Stores `change` applied to the value for `key`, or to `initial` when the key is
// absent. Looks the key up once; `initial` is evaluated eagerly and `change` runs
// once. Example: `counts.update(word, 0, fn n: n + 1)` counts occurrences.
fn var Map[T: Hashable & Clonable, U: Clonable].update(
	key: T,
	initial: U,
	change: fn(U) U
) Unit: ...

/*
Keeps only the entries for which `keep(key, value)` is True, in place, like `List.retain`; the rest keep their insertion order.
`keep` is called once per entry in insertion order, before any removal.
Example: `cache.retain(fn key, hits: hits > 0)` evicts unused entries.
*/
fn var Map[T: Hashable & Clonable, U].retain(keep: fn(T, U) Bool) Unit:
	var doomed = List[T]()
	self.for_each(
		fn key,
		value:
			if not keep(key, value):
				doomed.append(key.clone())
	)
	for key in doomed:
		self.remove(key)

// One key-value pair returned by `Map.entries`.
export type MapEntry[T: Hashable, U]:
	// The lookup identity of the pair; unique within its map under Hashable equality.
	key: T
	// The payload stored for `key`; accessing this field can borrow from the entry.
	value: U

// A mutable collection of unique values using explicit `Hashable` value semantics.
export extern type Set[T: Hashable]

// Copies elements deeply into independent storage, retaining insertion order.
fn Set[T].clone() Set[T]: ...

// Reports whether this set has no elements.
fn Set[T].is_empty() Bool: ...

// Copies matching elements and their nested values in insertion order.
// Callbacks borrow the receiver; mutating it during traversal is rejected.
fn Set[T].filter(predicate: fn(T) Bool) Set[T]: ...

// Transforms elements into a fresh set, retaining the first equal result.
fn Set[T].map[U: Hashable](transform: fn(T) U) Set[U]: ...

// Reduces elements in insertion order, starting with initial.
fn Set[T].fold[A](initial: A, step: fn(A, T) A) A: ...

// Reduces elements in reverse insertion order, starting with initial.
fn Set[T].fold_right[A](initial: A, step: fn(A, T) A) A: ...

// Returns the original first matching element, or none.
fn Set[T].find(predicate: fn(T) Bool) T?: ...

// Searches from the end, returning the original last matching element.
fn Set[T].find_last(predicate: fn(T) Bool) T?: ...

// Stops at the first matching element; empty sets return False.
fn Set[T].any(predicate: fn(T) Bool) Bool: ...

// Stops at the first nonmatching element; empty sets return True.
fn Set[T].all(predicate: fn(T) Bool) Bool: ...

// Returns a new set with receiver values followed by right-only values in insertion
// order.
fn Set[T].union(other: Set[T]) Set[T]: ...

// Returns a new set of receiver values also in right, preserving receiver insertion
// order.
fn Set[T].intersection(other: Set[T]) Set[T]: ...

// Returns a new set of receiver values absent from right, preserving receiver
// insertion order.
fn Set[T].difference(other: Set[T]) Set[T]: ...

// Returns a new set of values in exactly one operand; leaves both operands
// unchanged.
fn Set[T].symmetric_difference(other: Set[T]) Set[T]: ...

// Tests whether every receiver value also occurs in right.
fn Set[T].is_subset_of(other: Set[T]) Bool: ...

// Tests whether every right value also occurs in the receiver.
fn Set[T].is_superset_of(other: Set[T]) Bool: ...

// Tests whether the operands have no common values.
fn Set[T].is_disjoint_from(other: Set[T]) Bool: ...

// Removes all values in place.
fn var Set[T].clear() Unit: ...

// Returns an owned list containing copies of values in insertion order.
fn Set[T].values() List[T]: ...

// Calls operation(value:) sequentially over the receiver in insertion order.
fn Set[T].for_each(operation: fn(T) Unit) Unit: ...

// Reports whether an equal value is present, using the element's Hashable
// implementation.
fn Set[T].contains(value: T) Bool: ...

// Returns the number of distinct values currently stored.
fn Set[T].length() Int: ...

// Adds a value in place; an equal value retains its original payload and position.
fn var Set[T].add(value: T) Unit: ...

// Removes an equal value in place; an absent value leaves it unchanged.
fn var Set[T].remove(value: T) Unit: ...

// Keeps only the values for which `keep` is True, in place, like `List.retain`; the
// rest keep their insertion order. Example: `seen.retain(fn n: n >= 0)`.
fn var Set[T: Hashable & Clonable].retain(keep: fn(T) Bool) Unit:
	var doomed = List[T]()
	self.for_each(
		fn value:
			if not keep(value):
				doomed.append(value.clone())
	)
	for value in doomed:
		self.remove(value)

// Two values of possibly different types, as produced by `List.zip`.
export type Pair[A, B]:
	// The value taken from the receiver list.
	first: A
	// The value taken from the argument list.
	second: B

// The two lists `List.partition` produces: elements the predicate accepted and the
// rest, each in original order.
export type Partition[T]:
	// Elements for which the predicate was True, in original order.
	matching: List[T]
	// Elements for which the predicate was False, in original order.
	rest: List[T]

// One list index and its corresponding value.
export type ListEntry[T]:
	// Zero-based position of the element in the list that produced this entry.
	index: Int
	// The element found at `index`.
	value: T

// The result of searching a sorted list. `index` is usable as an insertion position
// even when `found` is false. Example: `[1, 3, 3].binary_search(3)` returns
// `index: 1, found: true`; searching for 2 returns `index: 1, found: false`.
export type SearchResult:
	// The first index whose element is not less than the target, or the list's length
	// when every element is less.
	index: Int
	// True when the element at `index` compares equal to the target.
	found: Bool

// Creates a list containing independent copies of `value` repeated `count` times; the
// value must be Clonable.
export fn filled[T: Clonable](value: T, count: Int, max_items: Int?) List[T]!:
	limit := max_items.get(9223372036854775807)
	if count < 0 or limit < 0: return error(
		Error("collection: invalid input", kind: "EINVAL")
	)
	if count > limit or count > MAX_LIST_ITEMS: return error(
		Error("collection: limit exceeded", kind: "EOVERFLOW")
	)

	return ok([value.clone()].repeated(count))

// The largest list a native allocation accepts.
MAX_LIST_ITEMS := 268435456

// Creates the integers from `start` up to but excluding `end`, counting by one. Written
// `start..end`; the name `range` is not importable. The list is empty when
// `end <= start`. `for index in 0..count:` runs as a counter loop without allocating
// the list. As a stored list, more than about 268 million items is a fault; use
// `range_by` to bound the size with an error value.
fn range(start: Int, end: Int) List[Int]: ...

// Settings for `range_by`: an optional cap on the number of items.
export type RangeOptions:
	// Maximum list length; none adds no cap beyond the allocation limit.
	max_items: Int? = none

// Creates integers from `start` up to but excluding `end` using a nonzero `step`; a
// negative step counts down. Returns `EINVAL` for a zero step and `EOVERFLOW` when the
// list would exceed `max_items`.
export fn range_by(
	start: Int,
	end: Int,
	step: Int,
	options: RangeOptions = RangeOptions(),
) List[Int]!:
	return msrt_list_range_by(start, end, step, options.max_items)

// Builds a map from entries. Later entries replace earlier values for duplicate keys.
export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) Map[K, V]: ...

// Copies the inner lists' elements in order into one new list; elements must be
// Clonable. Example: `flatten([[1, 2], [3]])` returns `[1, 2, 3]`.
export fn flatten[T: Clonable](lists: List[List[T]]) List[T]:
	return msrt_list_flatten(lists)

// Reverses the elements of `items` in [start, end) in place; used by `rotate`.
fn reverse_span[T](var items: List[T], start: Int, end: Int) Unit:
	var low = start
	var high = end - 1

	while low < high:
		items.swap(low, high)
		low += 1
		high -= 1

import (
	panic from "@std/core.ms",
	StringBuilder from "@std/string_builder.ms",

	msrt_list_distinct,
	msrt_list_flatten,
	msrt_list_range_by from "@std/internal/collections.ms",
)

// The built-in integer and float types: the element types `sum` adds.
export type Numeric = Int | Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | Float | Float32
