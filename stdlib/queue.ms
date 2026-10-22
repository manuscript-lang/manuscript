import {panic} from "@std/core.ms"
import {range} from "@std/collections.ms"

# A mutable first-in, first-out queue. A queue is an owned value: a copy is an independent queue, like Deque and List.
# Omitted or none capacity grows as needed and adds no fixed queue limit.
export type Queue[T]:
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Pending values from `head`; `none` marks consumed slots. Internal state: use the operations, not this field.
    items: List[Optional[T]] = []
    # Index in `items` of the oldest value. Internal state.
    head: Int = 0

impl Queue[T]:
    # Adds a value, returning false when a bounded queue is full. A non-positive capacity faults.
    var fn enqueue(value: T) Bool:
        if let limit = self.capacity:
            if limit <= 0:
                panic(
                    "Queue: capacity must be between 1 and 9223372036854775807, found {limit}"
                )
            if self.length() >= limit:
                return false

        let count = self.items.length()

        if self.head > 0 and self.head * 2 >= count:
            var live: List[Optional[T]] = []
            for index in range(self.head, count):
                live.append(self.items.get(index))
            self.items = live
            self.head = 0

        self.items.append(some(value))
        return true

    # Removes and returns the oldest value, or `none` when empty.
    var fn dequeue() Optional[T]:
        if self.head >= self.items.length():
            return none

        let value = self.items.get(self.head)
        self.items.set(self.head, none)
        self.head += 1

        if self.head == self.items.length():
            self.items = []
            self.head = 0

        return value

    # Returns the oldest value without removing it, or none when the queue is empty.
    fn peek() Optional[T]:
        if self.head >= self.items.length():
            return none

        return self.items.get(self.head)

    # Returns the number of values currently waiting in the queue.
    fn length() Int:
        return self.items.length() - self.head

    # Reports whether dequeue and peek would return none.
    fn is_empty() Bool:
        return self.head >= self.items.length()

# Negative compare results put left before right; equal priorities remain FIFO.
# A priority queue is an owned value: a copy is an independent queue.
export type PriorityQueue[T]:
    # Constructor comparator: negative puts left first; ties dequeue in enqueue order.
    # Comparisons must stay consistent.
    compare: fn(left: T, right: T) Int
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Binary heap of values. Internal state: use the operations, not this field.
    heap: List[T] = []
    # Enqueue sequence number of each heap value, which breaks ties between equal priorities. Internal state.
    orders: List[Int] = []
    # Next enqueue sequence number. Internal state.
    next_order: Int = 0

impl PriorityQueue[T]:
    # Reports whether the entry at `a` dequeues before the entry at `b`.
    fn before(a: Int, b: Int) Bool:
        let order = self.compare(self.heap.get(a), self.heap.get(b))
        return order < 0 or (order == 0 and self.orders.get(a) < self.orders.get(b))

    # Exchanges two heap entries.
    var fn swap(a: Int, b: Int) Unit:
        let left = self.heap.get(a)
        self.heap.set(a, self.heap.get(b))
        self.heap.set(b, left)
        let left_order = self.orders.get(a)
        self.orders.set(a, self.orders.get(b))
        self.orders.set(b, left_order)

    # Adds a value, returning false when a bounded queue is full. A non-positive capacity faults.
    var fn enqueue(value: T) Bool:
        if let limit = self.capacity:
            if limit <= 0:
                panic(
                    "PriorityQueue: capacity must be between 1 and 9223372036854775807, found {limit}"
                )
            if self.heap.length() >= limit:
                return false

        self.heap.append(value)
        self.orders.append(self.next_order)
        self.next_order += 1
        var at = self.heap.length() - 1

        while at > 0:
            let parent = (at - 1) / 2
            if not self.before(at, parent):
                break

            self.swap(at, parent)
            at = parent

        return true

    # Removes and returns the next value by priority, or `none` when empty.
    var fn dequeue() Optional[T]:
        let count = self.heap.length()
        if count == 0:
            return none

        let top = self.heap.get(0)
        let last = self.heap.pop()
        let last_order = self.orders.pop()
        if count == 1:
            return some(top)

        if let entry = last:
            self.heap.set(0, entry)
        if let order = last_order:
            self.orders.set(0, order)
        let size = count - 1
        var at = 0

        while true:
            var child = at * 2 + 1
            if child >= size:
                break

            if child + 1 < size and self.before(child + 1, child):
                child += 1
            if not self.before(child, at):
                break

            self.swap(child, at)
            at = child

        return some(top)

    # Returns the next value by priority without removing it, or none when empty.
    fn peek() Optional[T]:
        if self.heap.length() == 0:
            return none

        return some(self.heap.get(0))

    # Returns the number of enqueued values, independent of their priorities.
    fn length() Int:
        return self.heap.length()

    # Reports whether the queue has no values to peek or dequeue.
    fn is_empty() Bool:
        return self.heap.length() == 0
