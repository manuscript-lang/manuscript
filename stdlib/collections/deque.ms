import Iterable from "@std/collections/iterable.ms"

/*
A growable double-ended queue: O(1) amortized push and pop at both ends and O(1) indexed reads.
Use `.clone()` for an independent deque when its elements are Clonable; assigning a deque transfers ownership.
Use Queue for plain FIFO work and Deque when either end is pushed or popped, such as a sliding window or work stealing.
*/
export type Deque[T]:
	// Ring-buffer storage; `none` marks unused slots. Internal state: use the
	// operations, not this field.
	slots: List[T?] = []
	// Index in `slots` of the front value. Internal state.
	start: Int = 0
	// Number of values held. Internal state; read it with `length()`.
	size: Int = 0

// Reports whether the deque holds no values.
fn Deque[T].is_empty() Bool:
	return self.size == 0

// Doubles the ring buffer. The full buffer holds the values from `start` to the end,
// then those before `start`; moving the first run to the end of the larger buffer keeps
// that order and moves each value once.
fn var Deque[T].grow() Unit:
	capacity := self.slots.length()
	var next = capacity * 2
	if next == 0:
		next = 4

	shift := next - capacity
	for slot in capacity..next:
		self.slots.append(none)

	// Growth moves every value, including resource owners; slices would copy.
	var at = capacity - 1

	while at >= self.start:
		moved := self.slots.replace(at, none)
		self.slots.set(at + shift, moved)
		at -= 1

	if capacity > 0:
		self.start += shift

// Returns the ring-buffer index of the value `offset` places after the front;
// `offset` is at most the capacity.
fn Deque[T].slot_of(offset: Int) Int:
	at := self.start + offset
	capacity := self.slots.length()
	if at >= capacity: return at - capacity

	return at

// Adds a value after the last one.
fn var Deque[T].push_back(value: T) Unit:
	if self.size == self.slots.length():
		self.grow()
	self.slots.set(self.slot_of(self.size), value)
	self.size += 1

// Adds a value before the first one.
fn var Deque[T].push_front(value: T) Unit:
	if self.size == self.slots.length():
		self.grow()
	if self.start == 0:
		self.start = self.slots.length()
	self.start -= 1
	self.slots.set(self.start, value)
	self.size += 1

// Removes and returns the first value, or `none` when empty.
fn var Deque[T].pop_front() T?:
	if self.size == 0: return none

	value := self.slots.replace(self.start, none)
	self.start += 1
	if self.start == self.slots.length():
		self.start = 0
	self.size -= 1
	return value

// Removes and returns the last value, or `none` when empty.
fn var Deque[T].pop_back() T?:
	if self.size == 0: return none

	index := self.slot_of(self.size - 1)
	value := self.slots.replace(index, none)
	self.size -= 1
	return value

// Returns the first value without removing it, or `none` when empty.
fn Deque[T].front() T?:
	if self.size == 0: return none
	return self.slots.get(self.start)

// Returns the last value without removing it, or `none` when empty.
fn Deque[T].back() T?:
	if self.size == 0: return none
	return self.slots.get(self.slot_of(self.size - 1))

// Removes every value and releases the storage.
fn var Deque[T].clear() Unit:
	self.slots = []
	self.start = 0
	self.size = 0

// Ring behaviour: a Deque is also a ring buffer that can be turned.
/*
Moves `count` values from the front to the back, one at a time, so the value `count` places in becomes the front;
a negative `count` moves values from the back to the front. Any magnitude is reduced modulo the length, and an empty deque is unchanged.
Example: with 1, 2, 3, 4 queued, `rotate(1)` leaves 2, 3, 4, 1.
*/
fn var Deque[T].rotate(count: Int) Unit:
	if self.size < 2: return

	var steps = count % self.size

	// Choose the shorter direction after reducing the signed count.
	// Half-turn ties keep their original direction; Int.min is never negated.
	if steps > self.size / 2:
		steps -= self.size
	else if steps < -(self.size / 2):
		steps += self.size

	while steps > 0:
		if value := self.pop_front():
			self.push_back(value)
		steps -= 1

	while steps < 0:
		if value := self.pop_back():
			self.push_front(value)
		steps += 1

// Returns a new list of copies of the values from front to back.
fn Deque[T: Clonable].to_list() List[T]:
	var out: List[T] = []
	for index in 0..self.size:
		if value := self.slots.get(self.slot_of(index)):
			out.append(value.clone())
	return out

// Returns the number of values in the deque.
fn Deque[T].length() Int:
	return self.size

// Returns the value at `index` counted from the front, or `none` when out of range.
// Negative indexes are out of range.
fn Deque[T].at(index: Int) T?:
	if index < 0 or index >= self.size: return none
	return self.slots.get(self.slot_of(index))
