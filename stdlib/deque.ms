import {range} from "@std/collections.ms"

# A growable double-ended queue: O(1) amortized push and pop at both ends and O(1) indexed reads.
# Written in Manuscript over a ring buffer, so a copy of a Deque is an independent deque.
# Use Queue for plain FIFO work and Deque when either end is pushed or popped, such as a sliding window or work stealing.
export type Deque[T]:
    # Ring-buffer storage; `none` marks unused slots. Internal state: use the operations, not this field.
    slots: List[Optional[T]] = []
    # Index in `slots` of the front value. Internal state.
    start: Int = 0
    # Number of values held. Internal state; read it with `length()`.
    size: Int = 0

impl Deque[T]:
    # Returns the number of values in the deque.
    fn length() Int:
        return self.size

    # Reports whether the deque holds no values.
    fn is_empty() Bool:
        return self.size == 0

    # Doubles the ring buffer, unwrapping values so the front lands at index 0.
    var fn grow() Unit:
        let capacity = self.slots.length()
        var next = capacity * 2
        if next == 0:
            next = 4

        if self.start != 0:
            let tail = self.slots.drop(self.start)
            let head = self.slots.take(self.start)
            self.slots = tail.concat(head)
            self.start = 0

        for slot in range(capacity, next):
            self.slots.append(none)

    # Returns the ring-buffer index of the value `offset` places after the front; `offset` is at most the capacity.
    fn slot_of(offset: Int) Int:
        let at = self.start + offset
        let capacity = self.slots.length()
        if at >= capacity:
            return at - capacity

        return at

    # Adds a value after the last one.
    var fn push_back(value: T) Unit:
        if self.size == self.slots.length():
            self.grow()
        self.slots.set(self.slot_of(self.size), some(value))
        self.size += 1

    # Adds a value before the first one.
    var fn push_front(value: T) Unit:
        if self.size == self.slots.length():
            self.grow()
        if self.start == 0:
            self.start = self.slots.length()
        self.start -= 1
        self.slots.set(self.start, some(value))
        self.size += 1

    # Removes and returns the first value, or `none` when empty.
    var fn pop_front() Optional[T]:
        if self.size == 0:
            return none

        let value = self.slots.get(self.start)
        self.slots.set(self.start, none)
        self.start += 1
        if self.start == self.slots.length():
            self.start = 0
        self.size -= 1
        return value

    # Removes and returns the last value, or `none` when empty.
    var fn pop_back() Optional[T]:
        if self.size == 0:
            return none

        let index = self.slot_of(self.size - 1)
        let value = self.slots.get(index)
        self.slots.set(index, none)
        self.size -= 1
        return value

    # Returns the first value without removing it, or `none` when empty.
    fn front() Optional[T]:
        if self.size == 0:
            return none

        return self.slots.get(self.start)

    # Returns the last value without removing it, or `none` when empty.
    fn back() Optional[T]:
        if self.size == 0:
            return none

        return self.slots.get(self.slot_of(self.size - 1))

    # Returns the value at `index` counted from the front, or `none` when out of range.
    # Negative indexes are out of range.
    fn at(index: Int) Optional[T]:
        if index < 0 or index >= self.size:
            return none

        return self.slots.get(self.slot_of(index))

    # Removes every value and releases the storage.
    var fn clear() Unit:
        self.slots = []
        self.start = 0
        self.size = 0

    # Returns a new list of the values from front to back.
    fn to_list() List[T]:
        var out: List[T] = []
        for index in range(0, self.size):
            if let value = self.slots.get(self.slot_of(index)):
                out.append(value)
        return out
