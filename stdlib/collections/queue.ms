// A mutable first-in, first-out queue. Assigning it moves it; `.clone()` makes an
// independent queue when its elements are Clonable. An omitted or `null` capacity
// means the queue grows as needed and has no limit.
export type Queue[T]:
	// Maximum number of items. Omitted or `null` means unbounded; a capacity of zero
	// or below is always full.
	capacity: Int?
	// Pending values from `head`; `null` marks consumed slots. Internal state: use the
	// operations, not this field.
	items: List[T?] = []
	// Index in `items` of the oldest value. Internal state.
	head: Int = 0

// Adds a value and returns true, or returns false when a bounded queue is full. A
// capacity of zero or below is always full.
fn var Queue[T].enqueue(move value: T) Bool:
	if limit := self.capacity:
		if self.length() >= limit: return false

	count := self.items.length()

	if self.head > 0 and self.head * 2 >= count:
		var live: List[T?] = []
		for index in self.head..count:
			live.append(self.items.replace(index, null))
		self.items = live
		self.head = 0

	self.items.append(value)
	return true

// Removes and returns the oldest value, or `null` when empty.
fn var Queue[T].dequeue() T?:
	if self.head >= self.items.length(): return null

	value := self.items.replace(self.head, null)
	self.head += 1

	if self.head == self.items.length():
		self.items = []
		self.head = 0

	return value

// Returns the oldest value without removing it, or `null` when the queue is empty.
fn Queue[T].peek() T?:
	if self.head >= self.items.length(): return null
	return self.items.get(self.head)

// Reports whether `dequeue` and `peek` would return `null`.
fn Queue[T].is_empty() Bool:
	return self.head >= self.items.length()

// Returns the number of values currently waiting in the queue.
fn Queue[T].length() Int:
	return self.items.length() - self.head

// Returns the value `index` places after the oldest, or `null` when out of range;
// negative indexes count from the newest, as `List.get` does.
fn Queue[T].get(index: Int) T?:
	at := if index < 0: index + self.length() else: index
	if at < 0 or at >= self.length(): return null

	return self.items.get(self.head + at)

// Internal: orders two values: negative when `left` dequeues first, zero when equal
// and positive when `right` dequeues first.
fn order[T: Comparable](left: T, right: T) Int:
	return left.compare(right)

// A waiting value and its enqueue sequence number.
export type HeapEntry[T]:
	// The waiting value. Internal state of `PriorityQueue`.
	value: T
	// Enqueue sequence number; the smaller dequeues first among equal priorities.
	// Internal state.
	order: Int

// A queue whose values dequeue in their `Comparable` order, smallest first; equal
// priorities stay first in, first out. To order by something else, wrap the value in a
// record that implements `Comparable`. Assigning a priority queue moves it; `.clone()`
// makes an independent queue when its elements are Clonable.
export type PriorityQueue[T: Comparable]:
	// Maximum number of items. Omitted or `null` means unbounded; a capacity of zero
	// or below is always full.
	capacity: Int?
	// Binary heap of waiting values, each with its enqueue sequence number (the smaller
	// breaks ties between equal priorities). One list, so the two never fall out of
	// step. Internal state: use the operations, not this field.
	heap: List[HeapEntry[T]] = []
	// Next enqueue sequence number. Internal state.
	next_order: Int = 0

// Reports whether the entry at `a` dequeues before the entry at `b`.
fn PriorityQueue[T].before(a: Int, b: Int) Bool:
	first := self.heap[a]
	second := self.heap[b]
	order := order(first.value, second.value)
	return order < 0 or (order == 0 and first.order < second.order)

// Exchanges the heap entries at `a` and `b`.
fn var PriorityQueue[T].swap_entries(a: Int, b: Int) Void:
	self.heap.swap(a, b)

// Moves the entry at `start` up, but no higher than `floor`, while it dequeues
// before its parent.
fn var PriorityQueue[T].sift_up(start: Int, floor: Int) Void:
	var at = start

	while at > floor:
		parent := (at - 1) / 2
		if not self.before(at, parent): break

		self.swap_entries(at, parent)
		at = parent

/*
Moves the entry at `start` down the path of earlier children to the bottom, then back up to where it belongs:
one comparison per level on the way down instead of two, since a displaced last entry usually belongs near the bottom.
The loop runs while the entry has a left child, and the guards on `at` let the compiler prove every index in range.
*/
fn var PriorityQueue[T].sift_down(start: Int) Void:
	size := self.heap.length()
	parents := size / 2
	var at = start

	while at >= 0 and at < parents:
		left := at * 2 + 1
		right := left + 1

		if right < size and self.before(right, left):
			self.swap_entries(right, at)
			at = right
		else:
			self.swap_entries(left, at)
			at = left

	self.sift_up(at, start)

// Adds a value and returns true, or returns false when a bounded queue is full. A
// capacity of zero or below is always full.
fn var PriorityQueue[T].enqueue(move value: T) Bool:
	if limit := self.capacity:
		if self.heap.length() >= limit: return false
	self.heap.append(HeapEntry(value: value, order: self.next_order))
	self.next_order += 1
	self.sift_up(self.heap.length() - 1, 0)
	return true

// Removes and returns the next value by priority, or `null` when empty.
fn var PriorityQueue[T].dequeue() T?:
	count := self.heap.length()
	if count == 0: return null

	self.swap_entries(0, count - 1)

	top := self.heap.pop()
	self.sift_down(0)
	return top.map(fn entry: entry.value)

// Returns the next value by priority without removing it, or `null` when empty.
fn PriorityQueue[T].peek() T?:
	if self.heap.is_empty(): return null
	return self.heap[0].value

// Reports whether the queue has no values to peek or dequeue.
fn PriorityQueue[T].is_empty() Bool:
	return self.heap.is_empty()

// Returns the number of enqueued values, independent of their priorities.
fn PriorityQueue[T].length() Int:
	return self.heap.length()

// Returns the value at `index` in heap order, or `null` when out of range; only index
// 0 is known to be the next to dequeue. Negative indexes count from the end of the heap
// array.
fn PriorityQueue[T].get(index: Int) T?:
	at := if index < 0: index + self.heap.length() else: index
	if at < 0 or at >= self.heap.length(): return null

	return self.heap[at].value
