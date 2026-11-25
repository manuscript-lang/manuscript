/*
An ordered mutable collection with indexing, iteration and transformations.
Start with a literal such as `["docs", "release"]`; use `var` when you want to append, remove or replace items.
A list has one owner; `clone()` makes a deep copy, and `xs[i]` and accessors such as `first` borrow elements.
`List[T]()` creates an empty list. `List[T](reserve: n)` also preallocates room for `n` items without changing the length; a negative `n` reserves nothing.
*/
export type List[T] {
	// Constructor-only capacity hint in items: room for this many elements is allocated
	// up front. The list starts empty. `null` or a negative value reserves nothing.
	reserve Int?
}

// Returns an element, or `default` when the index is out of range; negative indexes are
// relative to the end.
fn hold List[T].get_or(index Int, default T?) &T {
	count := self.length()
	position := index
	if index < 0 { position = count + index }
	if position >= 0 and position < count { return self[position] }

	match default {
		value => return value
		null => return self[index]
	}
}

// Returns the first element, or `null` when the list is empty.
fn hold List[T].first() &T? {
	if self.is_empty() { return null }
	return self[0]
}

// Returns the last element, or `null` when the list is empty.
fn hold List[T].last() &T? {
	if self.is_empty() { return null }
	return self[-1]
}

// Reports whether the list has no elements.
fn List[T].is_empty() Bool { ... }

// Inserts `value` at index 0 in place, shifting existing elements one position
// later.
fn var List[T].prepend(move value T) Void { ... }

// Inserts `value` before `index` in place; negative indexes count from the end.
// Requires -length() <= index <= length(). An index of length() appends; any other
// invalid index faults.
fn var List[T].insert(index Int, move value T) Void { ... }

// Removes and returns the last element in place, or `null` for an empty list.
fn var List[T].pop() T? { ... }

// Replaces an element in place; negative indexes count from the end.
// Invalid indexes fault.
fn var List[T].set(index Int, move value T) Void { ... }

// Stores `value` at `index` in place and returns the element that was there. Both
// move without copying. Negative indexes count from the end; invalid indexes fault.
fn var List[T].replace(index Int, move value T) T { ... }

// Exchanges the elements at `i` and `j` in place without copying them; equal indexes
// change nothing. Negative indexes count from the end; invalid indexes fault.
fn var List[T].swap(i, j Int) Void { ... }

/*
Removes the element at `index` in place; negative indexes count from the end.
Invalid indexes fault.
Later elements shift down. Values left in spare backing capacity are not cleared.
*/
fn var List[T].remove(index Int) Void { ... }

// Reverses this list in place.
fn var List[T].reverse() Void { ... }

// Sorts the list in place, stably, in the order `compare` defines, as `sorted` does.
// Comparable elements also have `sort()` without a comparator. Example:
// `var xs = [3, 1, 2]` then `xs.sort(fn a, b: b - a)` leaves `[3, 2, 1]`.
fn var List[T].sort(compare fn(T, T) Int) Void { ... }

// Returns the zero-based index of the first element for which `predicate` is true,
// or `null`.
fn List[T].find_index(predicate fn(T) Bool) Int? {
	for i in 0..self.length() {
		if predicate(self[i]) { return i }
	}
	return null
}

// Searches from the end and returns the last matching zero-based index, or `null`.
fn List[T].find_last_index(predicate fn(T) Bool) Int? {
	var i = self.length() - 1

	while i >= 0 {
		if predicate(self[i]) { return i }

		i -= 1
	}

	return null
}

// Counts the values for which `predicate` is true, calling it once per element in
// order.
fn List[T].count(predicate fn(T) Bool) Int {
	var total = 0
	for item in self {
		if predicate(item) { total += 1 }
	}
	return total
}

// Reports whether at least one value satisfies `predicate`.
fn List[T].any(predicate fn(T) Bool) Bool {
	for item in self {
		if predicate(item) { return true }
	}
	return false
}

// Reports whether every value satisfies `predicate`; an empty list returns true.
fn List[T].all(predicate fn(T) Bool) Bool {
	for item in self {
		if not predicate(item) { return false }
	}
	return true
}

// Calls `operation(value)` on each element in order. The traversal covers the list's
// initial length, so an `append` during the loop does not extend it, while element
// writes can affect later calls. A callback that takes its parameter as `var` changes
// the element in place, and the receiver must then be `var`; a reading callback works
// on any list.
fn List[T].for_each(operation fn(var T) Void) Void {
	for index in 0..self.length() {
		operation(self[index])
	}
}

// Returns a new list holding `transform` applied to each element in order; the
// receiver is unchanged.
fn List[T].map[U](transform fn(T) U) List[U] {
	var out = List[U](reserve: self.length())
	for item in self {
		out.append(transform(item))
	}
	return out
}

// Calls `transform` on each element in order and concatenates the returned lists
// into one new list; the receiver is unchanged.
fn List[T].flat_map[U](transform fn(T) List[U]) List[U] {
	var out = List[U]()
	for item in self {
		out.splice(out.length(), 0, transform(item))
	}
	return out
}

// Combines the values from left to right with `step`, starting with `initial`.
fn List[T].fold[A](move initial A, step fn(A, T) A) A {
	var acc = initial
	for item in self {
		acc = step(acc, item)
	}
	return acc
}

// Combines the values from right to left with `step`, starting with `initial`.
fn List[T].fold_right[A](initial A, step fn(A, T) A) A {
	var acc = initial
	var i = self.length() - 1

	while i >= 0 {
		acc = step(acc, self[i])
		i -= 1
	}

	return acc
}

/*
Replaces `delete_count` elements starting at `start` in place with the elements of `replacement`, which is consumed.
Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault and are not clamped.
Removed elements are dropped, and replacement elements move into the receiver. The receiver and the replacement cannot be the same list.
*/
fn var List[T].splice(start, delete_count Int, move replacement List[T]) Void { ... }

// Returns a new list of the zero-based indexes 0 through length() - 1.
fn List[T].keys() List[Int] { ... }

// Adds `value` at the end in place.
fn var List[T].append(move value T) Void { ... }

// Returns the number of elements.
fn List[T].length() Int { ... }

// Adds the elements from left to right with `+` in the element type's own
// arithmetic: integer overflow faults and floats follow their width. An empty list
// sums to zero.
// Example: `[1, 2, 3].sum()` is `6`; `[1.5, 2.5].sum()` is `4.0`.
fn List[T Numeric].sum() T {
	var total T = 0
	for x in self {
		total += x
	}
	return total
}

// Returns a deep copy with independent list and nested value storage.
fn List[T Clonable].clone() List[T] { ... }

// Returns the elements in [start, end) as a view of this list: it keeps the list
// unchangeable until its last use, and nothing is copied. Use `.clone()` to keep it.
// Negative bounds are relative to the end; bounds outside 0 <= start <= end <=
// length() return an `Error` of kind `ERANGE`.
fn hold List[T Clonable].slice(start, end Int) &List[T]! { ... }

// Returns a new list with copies of the first `count` elements, or of all of them
// when `count` exceeds the length. The receiver is unchanged; a count of zero or
// below gives an empty list.
fn List[T Clonable].take(count Int) List[T] { ... }

// Returns a new list with copies of the elements after the first `count`. The
// receiver is unchanged; a count of zero or below drops nothing.
fn List[T Clonable].drop(count Int) List[T] { ... }

// Copies the leading elements for which `predicate` holds, stopping at the first one
// that fails it. Example: `[1, 2, 5, 1].take_while(x => x < 3)` is `[1, 2]`.
fn List[T Clonable].take_while(predicate fn(T) Bool) List[T] {
	return self.take(self.find_index(x => not predicate(x)) or self.length())
}

// Copies the elements from the first one that fails `predicate` to the end, so it is
// what `take_while` leaves. Example: `[1, 2, 5, 1].drop_while(x => x < 3)` is
// `[5, 1]`.
fn List[T Clonable].drop_while(predicate fn(T) Bool) List[T] {
	return self.drop(self.find_index(x => not predicate(x)) or self.length())
}

// Splits the list into consecutive chunks of `size` elements, as copies. The last
// chunk may be shorter. An empty list, or a `size` of zero or less, gives an empty
// list.
fn List[T Clonable].chunks(size Int) List[List[T]] { ... }

// Returns each run of `size` consecutive elements as an overlapping copy, in order.
// A list shorter than `size`, or a `size` of zero or less, gives an empty list.
// Windows are copies; `slice` and `take` do not borrow.
fn List[T Clonable].windows(size Int) List[List[T]] { ... }

// Calls `predicate` once per element in order and splits the elements into those
// that matched and the rest, each in the original order.
fn List[T Clonable].partition(predicate fn(T) Bool) Partition[T] {
	var matching = List[T]()
	var rest = List[T]()

	for item in self {
		if predicate(item) {
			matching.append(item.clone())
		} else {
			rest.append(item.clone())
		}
	}

	return Partition[T](matching, rest)
}

// Returns an independent reversed copy, including nested values.
fn List[T Clonable].reversed() List[T] {
	var out = self.clone()
	out.reverse()
	return out
}

/*
Returns a new list ordered by `compare`; the receiver is unchanged. The sort is stable: equal elements keep their order.
A negative, zero or positive result puts the first argument before, level with or after the second. Comparable elements also have `sorted()` without a comparator.
Example: `names.sorted(fn a, b: a.length() - b.length())` orders by length.
*/
fn List[T Clonable].sorted(compare fn(T, T) Int) List[T] { ... }

// Returns a new list of the values for which `predicate` is true, in their original
// order.
fn List[T Clonable].filter(predicate fn(T) Bool) List[T] {
	var out = List[T]()
	for item in self {
		if predicate(item) { out.append(item.clone()) }
	}
	return out
}

// Returns the first element for which `predicate` is true as a view of this list, or
// `null`. Later elements are not tested after a match. Use `.clone()` to keep it.
fn hold List[T].find(predicate fn(T) Bool) &T? {
	for item in self {
		if predicate(item) { return item }
	}
	return null
}

// Searches from the end and returns the last element for which `predicate` is true as a
// view of this list, or `null`.
fn hold List[T].find_last(predicate fn(T) Bool) &T? {
	var i = self.length() - 1

	while i >= 0 {
		if predicate(self[i]) { return self[i] }

		i -= 1
	}

	return null
}

// Sets the elements in [start, end) to copies of `value` in place. Bounds must
// satisfy 0 <= start <= end <= length(); a negative or larger bound faults instead
// of counting from the end. An empty range changes nothing.
fn var List[T Clonable].fill(move value T, start, end Int) Void { ... }

// Copies the elements in [start, end) to begin at index `target`, in place. The
// list never grows: copying stops at the end of the list. Source bounds must
// satisfy 0 <= start <= end <= length() and a target must be within 0 through
// length(); otherwise the call faults.
fn var List[T Clonable].copy_within(target, start, end Int) Void { ... }

// Returns a new list of `ListEntry` records pairing each zero-based index with its
// element, in order.
fn List[T Clonable].entries() List[ListEntry[T]] {
	var out = List[ListEntry[T]]()
	for i in 0..self.length() {
		out.append(ListEntry[T](i, self[i].clone()))
	}
	return out
}

// Returns a new list holding this list's elements followed by `other`; neither
// operand is changed.
fn List[T Clonable].concat(other List[T]) List[T] { ... }

// Pairs elements by position into fresh `Pair` records, stopping at the shorter
// list; both lists are unchanged.
fn List[T Clonable].zip[U Clonable](other List[U]) List[Pair[T, U]] {
	var out = List[Pair[T, U]]()
	size := if self.length() < other.length() { self.length() } else { other.length() }
	for i in 0..size {
		out.append(Pair[T, U](self[i].clone(), other[i].clone()))
	}
	return out
}

// Calls `key` once per element in order and returns a map from each distinct key to
// the elements that produced it. Keys appear in first-seen order, and each group
// keeps the original element order.
fn List[T Clonable].group_by[K Hashable](key fn(T) K) Map[K, List[T]] { ... }

// Counts how many times each distinct element occurs. Keys appear in first-seen order.
// Example: `["a", "b", "a"].counts()` maps `"a"` to 2 and `"b"` to 1.
fn List[T Hashable & Clonable].counts() Map[T, Int] {
	var out = Map[T, Int]()
	for x in self {
		out.update(x, 0, n => n + 1)
	}
	return out
}

// Reports whether any element equals `value`, using the element type's `Equal`
// implementation. An empty list returns false.
fn List[T Equal].contains(value T) Bool {
	return self.any(x => x.equals(value))
}

// Returns the zero-based index of the first element equal to `value`, or `null`.
// Elements must implement `Equal`.
fn List[T Equal].index_of(value T) Int? {
	for i in 0..self.length() {
		if self[i].equals(value) { return i }
	}
	return null
}

// Returns the zero-based index of the last element equal to `value`, or `null`.
// Elements must implement `Equal`.
fn List[T Equal].last_index_of(value T) Int? {
	var i = self.length() - 1

	while i >= 0 {
		if self[i].equals(value) { return i }

		i -= 1
	}

	return null
}

// Returns a new list with a copy of the first of each group of equal elements, in
// order. Elements must implement `Equal` and be Clonable.
fn List[T Equal & Clonable].distinct() List[T] {
	return msrt_list_distinct(self)
}

// Returns a new set of the distinct elements, using `Hashable` equality. The first
// of equal elements is kept, in insertion order.
fn List[T Hashable & Clonable].to_set() Set[T] {
	var out = Set[T]()
	for x in self {
		out.add(x.clone())
	}
	return out
}

/*
Joins the elements' interpolation text (`"{value}"`) with `separator` between neighbors; an empty list returns an empty string.
Strings join as they are and numbers as decimal text. A record or alternative joins in its structural form.
Example: `[1, 2, 3].join(",")` is `"1,2,3"`.
*/
fn List[T].join(separator String) String {
	var out = ""

	for i in 0..self.length() {
		if i > 0 {
			out += separator
		}
		out += f"{self[i]}"
	}

	return out
}

/*
Returns a new list in ascending natural order; the receiver is unchanged. The sort is stable: equal elements keep their order.
Float orders NaN above every other value.
Example: `[3, 1, 2].sorted()` is `[1, 2, 3]`.
*/
fn List[T Comparable & Clonable].sorted() List[T] {
	return self.sorted((a, b) => a.compare(b))
}

// Sorts the list in place, stably, in the same order as `sorted()`.
// Example: `var xs = [3, 1, 2]` then `xs.sort()` leaves `[1, 2, 3]`.
fn var List[T Comparable].sort() Void {
	self.sort((a, b) => a.compare(b))
}

/*
Searches in O(log n) comparisons without copying elements or changing the list.
The list must be in ascending natural order, as `sorted()` produces: comparisons must form a total order, with Float NaNs last.
Sortedness is not checked; a list in the wrong order gives an unspecified result.
Returns the index of the first element that compares equal, or the insertion position with `found: false`. An empty list returns index 0.
Example: `[1, 3, 3, 5].binary_search(3).index` is `1`; searching for 4 gives index 3 with `found: false`.
*/
fn List[T Comparable].binary_search(value T) SearchResult {
	// The insertion position is one of `length + 1` candidates in [base, base + size).
	// Each step halves the window by a count that depends only on `size`, and only
	// `base` depends on the comparison, as a select: the unpredictable result costs no
	// misprediction.
	count := self.length()
	var base = 0
	var size = count + 1

	while size > 1 {
		half := size / 2
		middle := base + half
		base = if self[middle - 1].compare(
			value
		) < 0 { middle } else { base }
		size -= half
	}

	return SearchResult(base, base < count and self[base].compare(value) == 0)
}

// Returns the least element as a view of this list, or `null` for an empty list. The
// first of equal elements wins. Example: `[3, 1, 2].min()` is `1`; `List[Int]().min()`
// is
// `null`.
fn hold List[T Comparable].min() &T? {
	if self.is_empty() { return null }

	var at = 0
	for i in 1..self.length() {
		if self[i].compare(self[at]) < 0 {
			at = i
		}
	}
	return self[at]
}

// Returns the greatest element as a view of this list, or `null` for an empty list. The
// first of equal elements wins. Example: `[3, 1, 2].max()` is `3`.
fn hold List[T Comparable].max() &T? {
	if self.is_empty() { return null }

	var at = 0
	for i in 1..self.length() {
		if self[i].compare(self[at]) > 0 {
			at = i
		}
	}
	return self[at]
}

/*
Returns a view of the element whose `key` is greatest, or `null` when the list is empty.
`key` is called once per element in order, and ties keep the earlier element.
Example: `["bb", "a", "ccc"].max_by(w => w.length())` is `"ccc"`.
*/
fn hold List[T].max_by[K Comparable](key fn(T) K) &T? {
	if self.is_empty() { return null }

	var at = 0
	var best = key(self[0])

	for i in 1..self.length() {
		k := key(self[i])

		if k.compare(best) > 0 {
			at = i
			best = k
		}
	}

	return self[at]
}

/*
Returns a view of the element whose `key` is least, or `null` when the list is empty.
`key` is called once per element in order, and ties keep the earlier element.
Example: `["bb", "a", "ccc"].min_by(w => w.length())` is `"a"`.
*/
fn hold List[T].min_by[K Comparable](key fn(T) K) &T? {
	if self.is_empty() { return null }

	var at = 0
	var best = key(self[0])

	for i in 1..self.length() {
		k := key(self[i])

		if k.compare(best) < 0 {
			at = i
			best = k
		}
	}

	return self[at]
}

/*
Keeps only the elements for which `keep` is true, in place and in their original order. `keep` is called once per element, in order.
Dropped elements are closed when they are resources; kept ones are moved, not copied.
Example: `var xs = [1, 2, 3, 4]` then `xs.retain(x => x % 2 == 0)` leaves `[2, 4]`.
*/
fn var List[T].retain(keep fn(T) Bool) Void {
	var kept = 0

	for i in 0..self.length() {
		if keep(self[i]) {
			self.swap(kept, i)
			kept += 1
		}
	}

	self.splice(kept, self.length() - kept, List[T]())
}

/*
Collapses each run of consecutive elements that `same` calls equal into its first element, in place.
`same(previous, next)` receives the last kept element and the candidate, so it runs once for each element after the first.
Example: `var xs = [1, 1, 2, 1]` then `xs.compact_by(fn a, b: a == b)` leaves `[1, 2, 1]`.
*/
fn var List[T].compact_by(same fn(T, T) Bool) Void {
	if self.length() < 2 { return }

	var kept = 1

	for i in 1..self.length() {
		if not same(self[kept - 1], self[i]) {
			self.swap(kept, i)
			kept += 1
		}
	}

	self.splice(kept, self.length() - kept, List[T]())
}

/*
Moves every element `by` places toward the front in place, wrapping the first ones around to the end.
A negative `by` rotates toward the back, and any magnitude is reduced modulo the length. An empty list is unchanged.
Example: `var xs = [1, 2, 3, 4]` then `xs.rotate(1)` leaves `[2, 3, 4, 1]`.
*/
fn var List[T].rotate(by Int) Void {
	size := self.length()
	if size < 2 { return }

	shift := (by % size + size) % size
	if shift == 0 { return }

	reverse_span(self, 0, shift)
	reverse_span(self, shift, size)
	reverse_span(self, 0, size)
}

// Reports whether the list is already in the order `compare` defines, meaning no
// element sorts after its successor. Empty and one-element lists are sorted.
fn List[T].is_sorted_by(compare fn(T, T) Int) Bool {
	for i in 1..self.length() {
		if compare(self[i - 1], self[i]) > 0 { return false }
	}
	return true
}

/*
Collapses each run of consecutive equal elements into its first element, in place. Elements must implement `Equal`.
Sort first to remove every duplicate, or use `distinct()`, which keeps the first of all equal elements without sorting.
Example: `var xs = [1, 1, 2, 2, 1]` then `xs.compact()` leaves `[1, 2, 1]`.
*/
fn var List[T Equal].compact() Void {
	self.compact_by((a, b) => a.equals(b))
}

// Reports whether the list is in ascending natural order, the order `sorted()`
// produces; empty and one-element lists are. Example: `[1, 2, 2, 5].is_sorted()` is
// `true`.
fn List[T Comparable].is_sorted() Bool {
	return self.is_sorted_by((a, b) => a.compare(b))
}

// Returns a new list ordered by the natural order of `key(element)`. The receiver is
// unchanged and the sort is stable. `key` runs on every comparison, so keep it cheap.
// Example: `people.sorted_by_key(p => p.age)`.
fn List[T Clonable].sorted_by_key[K Comparable](key fn(T) K) List[T] {
	return self.sorted((a, b) => key(a).compare(key(b)))
}

// Returns a new list holding the elements `count` times over, in order. A `count` of
// zero or below gives an empty list. Example: `[1, 2].repeated(2)` is
// `[1, 2, 1, 2]`.
fn List[T Clonable].repeated(count Int) List[T] { ... }

// Appends a copy of every element of `other`, in order, to this list in place;
// `other` is unchanged. The argument cannot be the receiver. Example: after
// `var xs = [1]`, `xs.extend([2, 3])` leaves `xs` as `[1, 2, 3]`.
fn var List[T Clonable].extend(other List[T]) Void { ... }

// A mutable key-value collection that remembers insertion order. Keys use their
// `Hashable` implementation to decide equality.
export extern type Map[T Hashable, U]

// Reports whether this map has no entries.
fn Map[T, U].is_empty() Bool {
	return self.length() == 0
}

// Returns a new map with the same keys, each paired with `transform(key, value)`, in
// insertion order. Keys are copied into the new map.
fn Map[T Clonable, U].map[W](transform fn(T, U) W) Map[T, W] {
	var out = Map[T, W]()
	for key in self.keys() {
		out.add(key.clone(), transform(key, self[key]))
	}
	return out
}

// Combines the entries in insertion order with `step`, starting with `initial`.
fn Map[T, U].fold[A](initial A, step fn(A, T, U) A) A {
	var acc = initial
	for key in self.keys() {
		acc = step(acc, key, self[key])
	}
	return acc
}

// Combines the entries in reverse insertion order with `step`, starting with
// `initial`.
fn Map[T, U].fold_right[A](initial A, step fn(A, T, U) A) A {
	var acc = initial
	keys := self.keys()
	var i = keys.length() - 1

	while i >= 0 {
		acc = step(acc, keys[i], self[keys[i]])
		i -= 1
	}

	return acc
}

// Reports whether any entry satisfies `predicate`, stopping at the first match. An
// empty map returns false.
fn Map[T, U].any(predicate fn(T, U) Bool) Bool {
	for key in self.keys() {
		if predicate(key, self[key]) { return true }
	}
	return false
}

// Reports whether every entry satisfies `predicate`, stopping at the first entry
// that does not. An empty map returns true.
fn Map[T, U].all(predicate fn(T, U) Bool) Bool {
	for key in self.keys() {
		if not predicate(key, self[key]) { return false }
	}
	return true
}

// Inserts `value` only when the key is absent. The argument is evaluated even when
// the key already exists.
fn var Map[T, U].add_default(move key T, move value U) Void { ... }

// Inserts `create(key)` only when the key is absent, calling `create` once. An
// existing key keeps its value and position, and `create` is not called.
fn var Map[T, U].add_default_from(move key T, create fn(T) U) Void {
	if self.contains(key) { return }

	value := create(key)
	self.add(key, value)
}

// Removes every entry in place.
fn var Map[T, U].clear() Void { ... }

// Returns the keys in insertion order as a view of this map: it keeps the map
// unchangeable until its last use. Use `.clone()` to keep the keys.
fn hold Map[T, U].keys() &List[T] { ... }

// Calls `operation(key, value)` for each entry in insertion order.
// A callback that takes `value` as `var` changes it in place, and the receiver must
// then be `var`.
fn Map[T Hashable, U].for_each(operation fn(T, var U) Void) Void {
	for key in self.keys() {
		operation(key, self[key])
	}
}

// Reports whether an equal key is present, using the key type's `Hashable`
// implementation.
fn Map[T, U].contains(key T) Bool { ... }

// Returns the value stored for an equal key, or `null` when the key is absent.
fn hold Map[T, U].get(key T) &U? { ... }

// Returns the number of entries.
fn Map[T, U].length() Int { ... }

// Inserts or replaces a value; replacement keeps the original key and insertion
// position.
fn var Map[T, U].add(move key T, move value U) Void { ... }

// Removes an equal key in place; the remaining entries keep their insertion order.
// An absent key changes nothing.
fn var Map[T, U].remove(move key T) Void { ... }

// Returns a deep copy with independent map and nested value storage.
fn Map[T Hashable & Clonable, U Clonable].clone() Map[T, U] {
	var out = Map[T, U]()
	for key in self.keys() {
		out.add(key.clone(), self[key].clone())
	}
	return out
}

// Returns a new map of copies of the entries for which `predicate` is true, in
// insertion order. The callback borrows the receiver, so changing the map during
// the traversal is rejected.
fn Map[T Hashable & Clonable, U Clonable].filter(predicate fn(T, U) Bool) Map[T, U] {
	var out = Map[T, U]()

	for key in self.keys() {
		value := self[key]
		if predicate(key, value) { out.add(key.clone(), value) }
	}

	return out
}

// Returns a new map with each key replaced by `transform(key, value)`, in insertion
// order, and the values copied. When two entries produce equal keys, the result keeps
// the first position and the last value.
fn Map[T Hashable & Clonable, U Clonable].map_keys[W Hashable](
	transform fn(T, U) W
) Map[W, U] {
	var out = Map[W, U]()

	for key in self.keys() {
		value := self[key]
		out.add(transform(key, value), value)
	}

	return out
}

// Returns the stored value, or `fallback` when the key is absent. The fallback is
// always evaluated, and the map is not changed.
fn Map[T Hashable, U Clonable].get_or(key T, fallback U) U { ... }

// Returns the first entry for which `predicate` is true as a new `MapEntry` holding
// copies of the key and value, or `null`.
fn Map[T Hashable & Clonable, U Clonable].find(
	predicate fn(T, U) Bool
) MapEntry[T, U]? {
	for key in self.keys() {
		value := self[key]
		if predicate(key, value) { return MapEntry(key: key.clone(), value: value) }
	}

	return null
}

// Searches from the end and returns the last entry for which `predicate` is true as
// a new `MapEntry` holding copies of the key and value, or `null`.
fn Map[T Hashable & Clonable, U Clonable].find_last(
	predicate fn(T, U) Bool
) MapEntry[T, U]? {
	keys := self.keys()
	var i = keys.length() - 1

	while i >= 0 {
		value := self[keys[i]]
		if predicate(keys[i], value) {
			return MapEntry(key: keys[i].clone(), value: value)
		}

		i -= 1
	}

	return null
}

// Returns the values in insertion order as a view of this map: it keeps the map
// unchangeable until its last use. Use `.clone()` to keep the values.
fn hold Map[T Hashable, U Clonable].values() &List[U] { ... }

// Returns a new list of `MapEntry` records in insertion order. Each record holds the
// key and value without copying them.
fn Map[T Hashable & Clonable, U Clonable].entries() List[MapEntry[T, U]] {
	var out = List[MapEntry[T, U]]()
	keys := self.keys()
	var at = 0

	for value in self.values() {
		out.append(MapEntry(key: keys[at].clone(), value: value))
		at += 1
	}

	return out
}

// Copies every entry of `other` into this map in place. Existing keys keep their
// position and key but take the value from `other`; new keys append in `other`
// order. `other` is unchanged.
fn var Map[T Hashable, U Clonable].merge(other Map[T, U]) Void { ... }

// Stores `change` applied to the value for `key`, or to `initial` when the key is
// absent. The key is probed once, `initial` is always evaluated, and `change` runs once
// and must not use this map. The key is copied only when it is absent. Example:
// `counts.update(word, 0, n => n + 1)` counts occurrences.
fn var Map[T Hashable & Clonable, U].update(
	key T,
	move initial U,
	change fn(U) U
) Void { ... }

/*
Keeps only the entries for which `keep(key, value)` is true, in place, like `List.retain`. The rest keep their insertion order.
`keep` is called once per entry in insertion order, before any removal.
Example: `cache.retain(fn key, hits: hits > 0)` evicts unused entries.
*/
fn var Map[T Hashable & Clonable, U].retain(keep fn(T, U) Bool) Void {
	var doomed = List[T]()
	for key in self.keys() {
		if not keep(key, self[key]) {
			doomed.append(key.clone())
		}
	}
	for key in doomed {
		self.remove(key)
	}
}

// One key-value pair returned by `Map.entries`.
export type MapEntry[T Hashable, U] {
	// The key; unique within its map under `Hashable` equality.
	key T
	// The value stored for `key`. Reading this field borrows from the entry.
	value U
}

// A mutable collection of unique values that remembers insertion order. Values use
// their `Hashable` implementation to decide equality.
export extern type Set[T Hashable]

// Returns a deep copy with independent storage, in the same insertion order.
fn Set[T Hashable & Clonable].clone() Set[T] {
	var out = Set[T]()
	for value in self.values() {
		out.add(value.clone())
	}
	return out
}

// Reports whether this set has no elements.
fn Set[T].is_empty() Bool {
	return self.length() == 0
}

// Returns a new set of copies of the elements for which `predicate` is true, in
// insertion order. The callback borrows the receiver, so changing the set during the
// traversal is rejected.
fn Set[T Hashable & Clonable].filter(predicate fn(T) Bool) Set[T] {
	var out = Set[T]()
	for value in self.values() {
		if predicate(value) { out.add(value.clone()) }
	}
	return out
}

// Returns a new set of `transform(element)` for each element; when results are
// equal, the first is kept.
fn Set[T].map[U Hashable](transform fn(T) U) Set[U] {
	var out = Set[U]()
	for value in self.values() {
		out.add(transform(value))
	}
	return out
}

// Combines the elements in insertion order with `step`, starting with `initial`.
fn Set[T].fold[A](initial A, step fn(A, T) A) A {
	var acc = initial
	for value in self.values() {
		acc = step(acc, value)
	}
	return acc
}

// Combines the elements in reverse insertion order with `step`, starting with
// `initial`.
fn Set[T].fold_right[A](initial A, step fn(A, T) A) A {
	var acc = initial
	values := self.values()
	var i = values.length() - 1

	while i >= 0 {
		acc = step(acc, values[i])
		i -= 1
	}

	return acc
}

// Returns the first element for which `predicate` is true as a view of this set, or
// `null`.
fn hold Set[T Hashable].find(predicate fn(T) Bool) &T? {
	// Workaround for #6943: iterate a bound view, not the call, so a record element
	// borrows.
	values := self.values()
	for value in values {
		if predicate(value) { return value }
	}
	return null
}

// Searches from the end and returns the last element for which `predicate` is true as a
// view of this set, or `null`.
fn hold Set[T Hashable].find_last(predicate fn(T) Bool) &T? {
	values := self.values()
	var i = values.length() - 1

	while i >= 0 {
		if predicate(values[i]) { return values[i] }

		i -= 1
	}

	return null
}

// Reports whether any element satisfies `predicate`, stopping at the first match. An
// empty set returns false.
fn Set[T].any(predicate fn(T) Bool) Bool {
	for value in self.values() {
		if predicate(value) { return true }
	}
	return false
}

// Reports whether every element satisfies `predicate`, stopping at the first one
// that does not. An empty set returns true.
fn Set[T].all(predicate fn(T) Bool) Bool {
	for value in self.values() {
		if not predicate(value) { return false }
	}
	return true
}

// Returns a new set with this set's values followed by the values only in `other`,
// in insertion order.
fn Set[T].union(other Set[T]) Set[T] { ... }

// Returns a new set of this set's values that are also in `other`, in this set's
// insertion order.
fn Set[T].intersection(other Set[T]) Set[T] { ... }

// Returns a new set of this set's values that are not in `other`, in this set's
// insertion order.
fn Set[T].difference(other Set[T]) Set[T] { ... }

// Returns a new set of the values that are in exactly one of the two sets. Neither
// set changes.
fn Set[T].symmetric_difference(other Set[T]) Set[T] { ... }

// Reports whether every value of this set is also in `other`.
fn Set[T].is_subset_of(other Set[T]) Bool { ... }

// Reports whether every value of `other` is also in this set.
fn Set[T].is_superset_of(other Set[T]) Bool { ... }

// Reports whether the two sets have no value in common.
fn Set[T].is_disjoint_from(other Set[T]) Bool { ... }

// Removes all values in place.
fn var Set[T].clear() Void { ... }

// Returns a new list of copies of the values in insertion order.
fn Set[T].values() List[T] { ... }

// Calls `operation(value)` for each value in insertion order.
fn Set[T].for_each(operation fn(T) Void) Void {
	for value in self.values() {
		operation(value)
	}
}

// Reports whether an equal value is present, using the element's `Hashable`
// implementation.
fn Set[T].contains(value T) Bool { ... }

// Returns the number of distinct values currently stored.
fn Set[T].length() Int { ... }

// Adds a value in place. If an equal value is already present, it keeps its original
// value and position.
fn var Set[T].add(move value T) Void { ... }

// Removes an equal value in place; an absent value changes nothing.
fn var Set[T].remove(move value T) Void { ... }

// Keeps only the values for which `keep` is true, in place, like `List.retain`. The
// rest keep their insertion order. Example: `seen.retain(n => n >= 0)`.
fn var Set[T Hashable & Clonable].retain(keep fn(T) Bool) Void {
	var doomed = List[T]()
	self.for_each(
		value => {
			if not keep(value) {
				doomed.append(value.clone())
			} }
	)
	for value in doomed {
		self.remove(value)
	}
}

// Two values of possibly different types, as produced by `List.zip`.
export type Pair[A, B] {
	// The value taken from the receiver list.
	first A
	// The value taken from the argument list.
	second B
}

// The two lists that `List.partition` returns: the elements the predicate accepted
// and the rest, each in original order.
export type Partition[T] {
	// Elements for which the predicate was true, in original order.
	matching List[T]
	// Elements for which the predicate was false, in original order.
	rest List[T]
}

// One list index and the value stored there.
export type ListEntry[T] {
	// Zero-based position of the element in the list that produced this entry.
	index Int
	// The element found at `index`.
	value T
}

// The result of searching a sorted list. `index` is usable as an insertion position
// even when `found` is false. Example: `[1, 3, 3].binary_search(3)` returns
// `index: 1, found: true`; searching for 2 returns `index: 1, found: false`.
export type SearchResult {
	// The first index whose element is not less than the target, or the list's length
	// when every element is less.
	index Int
	// True when the element at `index` compares equal to the target.
	found Bool
}

// Creates a list of `count` independent copies of `value`; the value must be
// Clonable. A negative `count` or `max_items` returns `EINVAL`, and a `count` above
// `max_items` or the allocation limit returns `EOVERFLOW`.
export fn filled[T Clonable](value T, count Int, max_items Int?) List[T]! {
	limit := max_items or 9223372036854775807
	if count < 0 or limit < 0 {
		return error(Error("collection: invalid input", kind: "EINVAL"))
	}
	if count > limit or count > MAX_LIST_ITEMS {
		return error(Error("collection: limit exceeded", kind: "EOVERFLOW"))
	}

	return ok([value.clone()].repeated(count))
}

// The largest list a native allocation accepts.
MAX_LIST_ITEMS := 268435456

// Creates the integers from `start` up to but excluding `end`, counting by one. It is
// written `start..end`; the name `range` is not importable. The list is empty when
// `end <= start`. A loop such as `for index in 0..count:` runs as a counter without
// allocating the list. Storing a list of more than about 268 million items is a
// fault; use `range_by` to bound the size with an error value instead.
fn range(start, end Int) List[Int] {
	var out = List[Int](reserve: if end > start { end - start } else { 0 })
	var next = start

	while next < end {
		out.append(next)
		next += 1
	}

	return out
}

// Settings for `range_by`: an optional cap on the number of items.
export type RangeOptions {
	// Maximum list length; `null` adds no cap beyond the allocation limit.
	max_items Int? = null
}

// Creates the integers from `start` up to but excluding `end`, counting by a nonzero
// `step`; a negative step counts down. A zero step returns `EINVAL`, and a list that
// would exceed `options.max_items` returns `EOVERFLOW`.
export fn range_by(
	start,
	end,
	step Int,
	options RangeOptions = RangeOptions(),
) List[Int]! {
	return msrt_list_range_by(start, end, step, options.max_items)
}

// Builds a map from a list of entries. For duplicate keys, a later entry replaces the
// value of an earlier one.
export fn map_from_entries[K Hashable, V](
	entries List[MapEntry[K, V]]
) Map[K, V] { ... }

// Copies the inner lists' elements in order into one new list; elements must be
// Clonable. Example: `flatten([[1, 2], [3]])` returns `[1, 2, 3]`.
export fn flatten[T Clonable](lists List[List[T]]) List[T] {
	var total = 0
	for inner in lists {
		total += inner.length()
	}

	var out = List[T](reserve: total)
	for inner in lists {
		out.extend(inner)
	}
	return out
}

// Internal: reverses the elements of `items` in [start, end) in place, for `rotate`.
fn reverse_span[T](var items List[T], start, end Int) Void {
	var low = start
	var high = end - 1

	while low < high {
		items.swap(low, high)
		low += 1
		high -= 1
	}
}

import msrt_list_distinct, msrt_list_range_by from "@std/internal/collections.ms"

// The built-in integer and float types: the element types `sum` adds.
export type Numeric = Int | Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | Float | Float32
