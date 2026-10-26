from "@std/core.ms" import panic
from "@std/collections.ms" import range

# A mutable first-in, first-out queue. A queue is an owned value: a copy is an independent queue, like Deque and List.
# Omitted or none capacity grows as needed and adds no fixed queue limit.
export type Queue[T: Clonable]:
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Pending values from `head`; `none` marks consumed slots. Internal state: use the operations, not this field.
    items: List[Optional[T]] = []
    # Index in `items` of the oldest value. Internal state.
    head: Int = 0

impl Queue[T]:
    # Adds a value, returning False when a bounded queue is full. A non-positive capacity faults.
    var def enqueue(value: T) -> Bool:
        if let limit = self.capacity:
            if limit <= 0:
                panic(
                    f"Queue: capacity must be between 1 and 9223372036854775807, found {limit}"
                )
            if self.length() >= limit:
                return False

        let count = self.items.length()

        if self.head > 0 and self.head * 2 >= count:
            var live: List[Optional[T]] = []
            for index in range(self.head, count):
                live.append(self.items.get(index).clone())
            self.items = live
            self.head = 0

        self.items.append(some(value))
        return True

    # Removes and returns the oldest value, or `none` when empty.
    var def dequeue() -> Optional[T]:
        if self.head >= self.items.length():
            return none

        let value = self.items.get(self.head).clone()
        self.items.set(self.head, none)
        self.head += 1

        if self.head == self.items.length():
            self.items = []
            self.head = 0

        return value

    # Returns the oldest value without removing it, or none when the queue is empty.
    def peek() -> ref Optional[T]:
        if self.head >= self.items.length():
            return none

        return self.items.get(self.head)

    # Returns the number of values currently waiting in the queue.
    def length() -> Int:
        return self.items.length() - self.head

    # Reports whether dequeue and peek would return none.
    def is_empty() -> Bool:
        return self.head >= self.items.length()

# One waiting value of a PriorityQueue with the sequence number that breaks ties between equal priorities.
# Internal state of the queue's heap: use the queue's operations, not this type.
export type PriorityEntry[T: Clonable]:
    # The queued value, returned unchanged by dequeue and peek.
    value: T
    # Enqueue sequence number: of two equal priorities the smaller dequeues first.
    order: Int

# Negative compare results put left before right; equal priorities remain FIFO.
# A priority queue is an owned value: a copy is an independent queue.
export type PriorityQueue[T: Clonable]:
    # Constructor comparator: negative puts left first; ties dequeue in enqueue order.
    # Comparisons must stay consistent.
    compare: Callable[[T, T], Int]
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Binary heap of values with their enqueue sequence numbers, which break ties between equal priorities.
    # Internal state: use the operations, not this field.
    heap: List[PriorityEntry[T]] = []
    # Next enqueue sequence number. Internal state.
    next_order: Int = 0

impl PriorityQueue[T]:
    # Reports whether the entry at `a` dequeues before the entry at `b`.
    def before(a: Int, b: Int) -> Bool:
        let x = self.heap.get(a)
        let y = self.heap.get(b)
        let order = self.compare(x.value, y.value)
        return order < 0 or (order == 0 and x.order < y.order)

    # Reports whether an entry waiting to be placed dequeues before the entry at `b`.
    def before_entry(entry: PriorityEntry[T], b: Int) -> Bool:
        let other = self.heap.get(b)
        let result = self.compare(entry.value, other.value)
        return result < 0 or (result == 0 and entry.order < other.order)

    # Copies the entry at `from` over the entry at `to`, which the caller is about to overwrite.
    var def shift(from: Int, to: Int) -> Unit:
        self.heap.set(to, self.heap.get(from).clone())

    # Adds a value, returning False when a bounded queue is full. A non-positive capacity faults.
    var def enqueue(value: T) -> Bool:
        if let limit = self.capacity:
            if limit <= 0:
                panic(
                    f"PriorityQueue: capacity must be between 1 and 9223372036854775807, found {limit}"
                )
            if self.heap.length() >= limit:
                return False

        let entry = PriorityEntry[T](value: value, order: self.next_order)
        self.next_order += 1
        self.heap.append(entry.clone())

        var at = self.heap.length() - 1

        while at > 0:
            let parent = (at - 1) / 2
            if not self.before_entry(entry, parent):
                break

            self.shift(parent, at)
            at = parent

        self.heap.set(at, entry)
        return True

    # Removes and returns the next value by priority, or `none` when empty.
    var def dequeue() -> Optional[T]:
        let count = self.heap.length()
        if count == 0:
            return none

        let top = self.heap.get(0).value.clone()

        if count == 1:
            self.heap.pop()
            return some(top)

        # The last entry is placed from a hole at the root, and then dropped from the end of the list.
        let entry = self.heap.get(count - 1).clone()
        let size = count - 1
        var at = 0

        # Move the hole to the bottom along the earlier child, then lift the displaced entry back up:
        # one comparison per level on the way down instead of two.
        while True:
            var child = at * 2 + 1
            if child >= size:
                break

            if child + 1 < size and self.before(child + 1, child):
                child += 1
            self.shift(child, at)
            at = child

        while at > 0:
            let parent = (at - 1) / 2
            if not self.before_entry(entry, parent):
                break

            self.shift(parent, at)
            at = parent

        self.heap.set(at, entry)
        self.heap.pop()
        return some(top)

    # Returns the next value by priority without removing it, or none when empty.
    def peek() -> Optional[T]:
        if self.heap.length() == 0:
            return none

        return some(self.heap.get(0).value.clone())

    # Returns the number of enqueued values, independent of their priorities.
    def length() -> Int:
        return self.heap.length()

    # Reports whether the queue has no values to peek or dequeue.
    def is_empty() -> Bool:
        return self.heap.length() == 0
