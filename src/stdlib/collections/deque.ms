/*
A growable double-ended queue: O(1) amortized push and pop at both ends and O(1) indexed reads.
Use `.clone()` for an independent deque when its elements are Clonable; assigning a deque moves it.
Use `Queue` for plain first-in, first-out work, and `Deque` when either end is pushed or popped, such as a sliding window or work stealing.
*/
export type Deque[T] {
	// Ring-buffer storage; `null` marks unused slots. Internal state: use the
	// operations, not this field.
	slots List[T?] = []
	// Index in `slots` of the front value. Internal state.
	start Int = 0
	// Number of values held. Internal state; read it with `length()`.
	size Int = 0
}

// Reports whether the deque holds no values.
fn Deque[T].is_empty() Bool {
	return self.size == 0
}

// Internal: doubles the ring buffer. A full buffer holds the values from `start` to
// the end, then those before `start`; moving the first run to the end of the larger
// buffer keeps that order and moves each value once.
fn var Deque[T].grow() Void {
	capacity := self.slots.length()
	var next = capacity * 2
	if next == 0 {
		next = 4
	}

	shift := next - capacity
	for slot in capacity..next {
		self.slots.append(null)
	}

	// Growth moves every value, including resource owners; slices would copy.
	var at = capacity - 1

	while at >= self.start {
		moved := self.slots.replace(at, null)
		self.slots.set(at + shift, moved)
		at -= 1
	}

	if capacity > 0 {
		self.start += shift
	}
}

// Internal: returns the ring-buffer index of the value `offset` places after the
// front. `offset` is at most the capacity.
fn Deque[T].slot_of(offset Int) Int {
	at := self.start + offset
	capacity := self.slots.length()
	if at >= capacity { return at - capacity }

	return at
}

// Adds a value after the last one.
fn var Deque[T].push_back(move value T) Void {
	if self.size == self.slots.length() {
		self.grow()
	}
	self.slots.set(self.slot_of(self.size), value)
	self.size += 1
}

// Adds a value before the first one.
fn var Deque[T].push_front(move value T) Void {
	if self.size == self.slots.length() {
		self.grow()
	}
	if self.start == 0 {
		self.start = self.slots.length()
	}
	self.start -= 1
	self.slots.set(self.start, value)
	self.size += 1
}

// Removes and returns the first value, or `null` when empty.
fn var Deque[T].pop_front() T? {
	if self.size == 0 { return null }

	value := self.slots.replace(self.start, null)
	self.start += 1
	if self.start == self.slots.length() {
		self.start = 0
	}
	self.size -= 1
	return value
}

// Removes and returns the last value, or `null` when empty.
fn var Deque[T].pop_back() T? {
	if self.size == 0 { return null }

	index := self.slot_of(self.size - 1)
	value := self.slots.replace(index, null)
	self.size -= 1
	return value
}

// Returns the first value without removing it, or `null` when empty.
fn hold Deque[T].front() & T? {
	if self.size == 0 { return null }
	return self.slots[self.start]
}

// Returns the last value without removing it, or `null` when empty.
fn hold Deque[T].back() & T? {
	if self.size == 0 { return null }
	return self.slots[self.slot_of(self.size - 1)]
}

// Removes every value and releases the storage.
fn var Deque[T].clear() Void {
	self.slots = []
	self.start = 0
	self.size = 0
}

/*
Turns the deque like a ring buffer. Moves `by` values from the front to the back, one at a time, so the value `by` places in becomes the front;
a negative `by` moves values from the back to the front. Any magnitude is reduced modulo the length, and an empty deque is unchanged.
Example: with 1, 2, 3, 4 queued, `rotate(1)` leaves 2, 3, 4, 1.
*/
fn var Deque[T].rotate(by Int) Void {
	if self.size < 2 { return }

	var steps = by % self.size

	// Choose the shorter direction after reducing the signed `by`.
	// Half-turn ties keep their original direction; Int.min is never negated.
	if steps > self.size / 2 {
		steps -= self.size
	} else if steps < -(self.size / 2) {
		steps += self.size
	}

	while steps > 0 {
		value := self.pop_front()
		if value != null {
			self.push_back(value)
		}
		steps -= 1
	}

	while steps < 0 {
		value := self.pop_back()
		if value != null {
			self.push_front(value)
		}
		steps += 1
	}
}

// Returns a new list of copies of the values from front to back.
fn Deque[T Clonable].to_list() List[T] {
	var out List[T] = []

	for index in 0..self.size {
		value := self.slots[self.slot_of(index)]
		if value != null {
			out.append(value.clone())
		}
	}

	return out
}

// Returns the number of values in the deque.
fn Deque[T].length() Int {
	return self.size
}

// Returns the value at `index` counted from the front, or `null` when out of range;
// negative indexes count from the back, as `xs[i]` does.
fn hold Deque[T].get(index Int) & T? {
	at := if index < 0 { index + self.size } else { index }
	if at < 0 or at >= self.size { return null }

	return self.slots[self.slot_of(at)]
}
