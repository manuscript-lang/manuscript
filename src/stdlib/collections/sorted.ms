import panic from "@std/core.ms"

// One key-value pair of a SortedMap.
export type SortedEntry[K Comparable, V] {
	// The entry's key, which orders it within the map.
	key K
	// The value stored for `key`.
	value V
}

/*
A map kept in ascending key order, so lookups by position (`first`, `last`, `floor`, `ceiling`, `range`) are as cheap as lookups by key.
Keys use their `Comparable` order; keys that compare equal are the same key. Replacing a key's value keeps the original key.

It is a list of sorted chunks of at most 128 entries. `get`, `contains`, `floor` and `ceiling` take O(log n).
`add` and `remove` locate the key and shift entries within its chunk; splitting or removing a chunk also updates the chunk lists.
Use `clone()` for an independent deep copy. Use `Map` when you do not need sorted order and want average O(1) key lookup.
*/
export type SortedMap[K Comparable, V] {
	// Sorted chunks of keys; no chunk is empty. Internal state: use the operations, not
	// this field.
	key_chunks List[List[K]] = []
	// Values parallel to `key_chunks`. Internal state.
	value_chunks List[List[V]] = []
	// Number of entries. Internal state; read it with `length()`.
	size Int = 0
}

// Internal: returns the index of the first chunk whose last key is not below `key`,
// or the last chunk when every key is below it.
fn SortedMap[K, V].chunk_for(key K) Int {
	var low = 0
	var high = self.key_chunks.length() - 1

	while low < high {
		middle := (low + high) / 2
		chunk := self.key_chunks[middle]

		if order(chunk[chunk.length() - 1], key) < 0 {
			low = middle + 1
		} else {
			high = middle
		}
	}

	return low
}

// Internal: returns the index of the first key in chunk `c` that is not below
// `key`, or the chunk length when there is null.
fn SortedMap[K, V].lower_bound(c Int, key K) Int {
	var low = 0
	var high = self.key_chunks[c].length()

	while low < high {
		middle := (low + high) / 2

		if order(self.key_chunks[c][middle], key) < 0 {
			low = middle + 1
		} else {
			high = middle
		}
	}

	return low
}

// Returns the number of entries.
fn SortedMap[K, V].length() Int {
	return self.size
}

// Reports whether the map has no entries.
fn SortedMap[K, V].is_empty() Bool {
	return self.size == 0
}

// Reports whether an equal key is present.
fn SortedMap[K, V].contains(key K) Bool {
	if self.size == 0 { return false }

	c := self.chunk_for(key)
	at := self.lower_bound(c, key)
	return (
		at < self.key_chunks[c].length()
		and order(self.key_chunks[c][at], key) == 0
	)
}

// Returns the value stored for an equal key as a view of this map, or `null` when
// absent.
fn hold SortedMap[K, V].get(key K) &V? {
	if self.size == 0 { return null }

	c := self.chunk_for(key)
	at := self.lower_bound(c, key)
	if (at < self.key_chunks[c].length() and order(self.key_chunks[c][at], key) == 0) {
		return self.value_chunks[c][at]
	}

	return null
}

// Returns the value stored for an equal key, or `fallback` when absent, as a view of
// whichever it is.
fn hold SortedMap[K, V].get_or(key K, hold fallback V) &V {
	return self.get(key) or fallback
}

// Inserts a key or replaces the value of an equal key, which keeps its original
// key.
fn var SortedMap[K, V].add(move key K, move value V) Void {
	if self.size == 0 {
		self.key_chunks = [[key]]
		self.value_chunks = [[value]]
		self.size = 1
		return
	}

	c := self.chunk_for(key)
	at := self.lower_bound(c, key)

	if (at < self.key_chunks[c].length() and order(self.key_chunks[c][at], key) == 0) {
		self.value_chunks[c].set(at, value)
		return
	}

	self.key_chunks[c].insert(at, key)
	self.value_chunks[c].insert(at, value)
	self.size += 1
	if self.key_chunks[c].length() > 128 {
		self.split(c)
	}
}

// Internal: splits chunk `c` into two halves.
fn var SortedMap[K, V].split(c Int) Void {
	length := self.key_chunks[c].length()
	half := length / 2
	tail_keys := split_off(self.key_chunks[c], half)
	tail_values := split_off(self.value_chunks[c], half)
	self.key_chunks.insert(c + 1, tail_keys)
	self.value_chunks.insert(c + 1, tail_values)
}

// Removes an equal key; an absent key changes nothing.
fn var SortedMap[K, V].remove(key K) Void {
	if self.size == 0 { return }

	c := self.chunk_for(key)
	at := self.lower_bound(c, key)
	if (at >= self.key_chunks[c].length() or order(self.key_chunks[c][at], key) != 0) {
		return
	}

	self.remove_at(c, at)
}

// Internal: removes the entry at position `at` of chunk `c`, dropping the chunk when
// it empties.
fn var SortedMap[K, V].remove_at(c, at Int) Void {
	self.key_chunks[c].remove(at)
	self.value_chunks[c].remove(at)
	self.mend(c)
}

// Internal: moves the entry at position `at` of chunk `c` out without copying it.
fn var SortedMap[K, V].take_at(c, at Int) SortedEntry[K, V] {
	entry := SortedEntry(
		take_item(self.key_chunks[c], at),
		take_item(self.value_chunks[c], at),
	)
	self.mend(c)
	return entry
}

// Internal: moves the elements from `at` to the end out of `items` into a new list, in
// order, without copying them.
fn split_off[T](var items List[T], at Int) List[T] {
	var tail List[T] = []
	while items.length() > at {
		tail.append(items.pop() or panic("called Optional.get() on null"))
	}
	tail.reverse()
	return tail
}

// Internal: moves the element at `at` out of `items`, shifting the later ones down by
// swaps.
fn take_item[T](var items List[T], at Int) T {
	var i = at

	while i < items.length() - 1 {
		items.swap(i, i + 1)
		i += 1
	}

	return items.pop() or panic("called Optional.get() on null")
}

// Internal: restores the chunk bookkeeping after an entry left chunk `c`.
fn var SortedMap[K, V].mend(c Int) Void {
	self.size -= 1

	if self.key_chunks[c].is_empty() {
		self.key_chunks.remove(c)
		self.value_chunks.remove(c)
	}
}

// Removes every entry and releases the storage; the map is empty afterwards.
fn var SortedMap[K, V].clear() Void {
	self.key_chunks = []
	self.value_chunks = []
	self.size = 0
}

// Returns the smallest key, or `null` when empty. Look its value up with `get`.
fn hold SortedMap[K, V].first() &K? {
	if self.size == 0 { return null }
	return self.key_chunks[0][0]
}

// Returns the largest key, or `null` when empty. Look its value up with `get`.
fn hold SortedMap[K, V].last() &K? {
	if self.size == 0 { return null }

	c := self.key_chunks.length() - 1
	return self.key_chunks[c][self.key_chunks[c].length() - 1]
}

// Removes the entry with the smallest key and moves it out, or returns `null` when
// empty.
fn var SortedMap[K, V].pop_first() SortedEntry[K, V]? {
	if self.size == 0 { return null }
	return self.take_at(0, 0)
}

// Removes the entry with the largest key and moves it out, or returns `null` when
// empty.
fn var SortedMap[K, V].pop_last() SortedEntry[K, V]? {
	if self.size == 0 { return null }

	c := self.key_chunks.length() - 1
	return self.take_at(c, self.key_chunks[c].length() - 1)
}

// Returns the entry with the smallest key that is at least `key`, or `null`.
fn SortedMap[K Comparable & Clonable, V Clonable].ceiling(key K) SortedEntry[K, V]? {
	if self.size == 0 { return null }

	c := self.chunk_for(key)
	at := self.lower_bound(c, key)
	if at >= self.key_chunks[c].length() { return null }

	return SortedEntry(self.key_chunks[c][at].clone(), self.value_chunks[c][at].clone())
}

// Returns the entry with the largest key that is at most `key`, or `null`.
fn SortedMap[K Comparable & Clonable, V Clonable].floor(key K) SortedEntry[K, V]? {
	if self.size == 0 { return null }

	var c = self.chunk_for(key)
	var at = self.lower_bound(c, key)
	if (at < self.key_chunks[c].length() and order(self.key_chunks[c][at], key) == 0) {
		return SortedEntry(
			self.key_chunks[c][at].clone(),
			self.value_chunks[c][at].clone(),
		)
	}

	if at == 0 {
		if c == 0 { return null }

		c -= 1
		at = self.key_chunks[c].length()
	}

	at -= 1
	return SortedEntry(self.key_chunks[c][at].clone(), self.value_chunks[c][at].clone())
}

// Returns a new list of the entries with `low` <= key < `high`, in ascending order.
fn SortedMap[K Comparable & Clonable, V Clonable].range(
	low,
	high K,
) List[SortedEntry[K, V]] {
	var out List[SortedEntry[K, V]] = []
	if self.size == 0 { return out }

	var c = self.chunk_for(low)
	var at = self.lower_bound(c, low)

	while c < self.key_chunks.length() {
		keys := self.key_chunks[c]

		while at < keys.length() {
			if order(keys[at], high) >= 0 { return out }

			out.append(SortedEntry(keys[at].clone(), self.value_chunks[c][at].clone()))
			at += 1
		}

		c += 1
		at = 0
	}

	return out
}

// Returns a new list of the keys in ascending order.
fn SortedMap[K Comparable & Clonable, V Clonable].keys() List[K] {
	return joined(self.key_chunks, 0, self.key_chunks.length())
}

// Returns a new list of the values in ascending key order.
fn SortedMap[K Comparable & Clonable, V Clonable].values() List[V] {
	return joined(self.value_chunks, 0, self.value_chunks.length())
}

// Returns a new list of the entries in ascending key order.
fn SortedMap[K Comparable & Clonable, V Clonable].entries() List[SortedEntry[K, V]] {
	var out List[SortedEntry[K, V]] = []

	for c in 0..self.key_chunks.length() {
		keys := self.key_chunks[c]
		for at in 0..keys.length() {
			out.append(SortedEntry(keys[at].clone(), self.value_chunks[c][at].clone()))
		}
	}

	return out
}

// Calls `operation(key, value)` for each entry in ascending key order. It iterates
// over a snapshot, so `operation` may change the map.
fn SortedMap[K Comparable & Clonable, V Clonable].for_each(
	operation fn(K, V) Void
) Void {
	for entry in self.entries() {
		operation(entry.key, entry.value)
	}
}

// A set kept in ascending order, with the same `Comparable` ordering and costs as
// `SortedMap`. Members that compare equal are the same member. Use `clone()` for an
// independent deep copy.
export type SortedSet[T Comparable] {
	// Members as the keys of a map. Internal state: use the operations, not this field.
	members SortedMap[T, Bool] = SortedMap[T, Bool]()
}

// Returns the number of members.
fn SortedSet[T].length() Int {
	return self.members.length()
}

// Reports whether the set has no members.
fn SortedSet[T].is_empty() Bool {
	return self.members.is_empty()
}

// Reports whether an equal member is present.
fn SortedSet[T].contains(value T) Bool {
	return self.members.contains(value)
}

// Adds a member; an equal member already present is kept.
fn var SortedSet[T].add(move value T) Void {
	if not self.members.contains(value) {
		self.members.add(value, true)
	}
}

// Removes an equal member; an absent value changes nothing.
fn var SortedSet[T].remove(value T) Void {
	self.members.remove(value)
}

// Removes every member and releases the storage; the set is empty afterwards.
fn var SortedSet[T].clear() Void {
	self.members.clear()
}

// Returns the smallest member, or `null` when empty.
fn hold SortedSet[T].first() &T? {
	return self.members.first()
}

// Returns the largest member, or `null` when empty.
fn hold SortedSet[T].last() &T? {
	return self.members.last()
}

// Removes and returns the smallest member, or `null` when empty.
fn var SortedSet[T].pop_first() T? {
	entry := self.members.pop_first()
	if entry != null { return entry.key }

	return null
}

// Removes and returns the largest member, or `null` when empty.
fn var SortedSet[T].pop_last() T? {
	entry := self.members.pop_last()
	if entry != null { return entry.key }

	return null
}

// Returns the smallest member that is at least `value`, or `null`.
fn SortedSet[T Comparable & Clonable].ceiling(value T) T? {
	entry := self.members.ceiling(value)
	if entry != null { return entry.key.clone() }

	return null
}

// Returns the largest member that is at most `value`, or `null`.
fn SortedSet[T Comparable & Clonable].floor(value T) T? {
	entry := self.members.floor(value)
	if entry != null { return entry.key.clone() }

	return null
}

// Returns a new list of the members with `low` <= member < `high`, in ascending
// order.
fn SortedSet[T Comparable & Clonable].range(low, high T) List[T] {
	return self.members.range(low, high).map(entry => entry.key.clone())
}

// Returns a new list of the members in ascending order.
fn SortedSet[T Comparable & Clonable].values() List[T] {
	return self.members.keys()
}

// Internal: orders two keys: negative when `left` sorts first, zero when equal,
// positive when
// `right` sorts first.
fn order[T Comparable](left, right T) Int {
	return left.compare(right)
}

// Internal: returns one new list holding `chunks[low]` through `chunks[high - 1]`
// in order.
// Halving the range copies each element about log2(chunk count) times; folding left
// with `concat` would recopy every earlier chunk for each later one.
fn joined[T Clonable](chunks List[List[T]], low, high Int) List[T] {
	count := high - low
	if count == 0 { return [] }
	if count == 1 { return chunks[low].clone() }
	if count == 2 {
		return chunks[low].concat(chunks[low + 1])
	}

	middle := low + count / 2
	return joined(chunks, low, middle).concat(joined(chunks, middle, high))
}
