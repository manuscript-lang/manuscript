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
                live.append(self.items.replace(index, none))
            self.items = live
            self.head = 0

        self.items.append(value)
        return True

    # Removes and returns the oldest value, or `none` when empty.
    var def dequeue() -> Optional[T]:
        if self.head >= self.items.length():
            return none

        let value = self.items.replace(self.head, none)
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

# Negative compare results put left before right; equal priorities remain FIFO.
# A priority queue is an owned value: a copy is an independent queue.
export type PriorityQueue[T: Clonable]:
    # Constructor comparator: negative puts left first; ties dequeue in enqueue order.
    # Comparisons must stay consistent.
    compare: Callable[[T, T], Int]
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Binary heap of waiting values. Internal state: use the operations, not this field.
    heap: List[T] = []
    # Enqueue sequence number of each heap value, in step with `heap`; the smaller breaks ties between equal priorities. Internal state.
    orders: List[Int] = []
    # Next enqueue sequence number. Internal state.
    next_order: Int = 0

impl PriorityQueue[T]:
    # Reports whether the entry at `a` dequeues before the entry at `b`.
    def before(a: Int, b: Int) -> Bool:
        let order = self.compare(self.heap.get(a), self.heap.get(b))
        return order < 0 or (order == 0 and self.orders.get(a) < self.orders.get(b))

    # Exchanges the heap entries at `a` and `b`.
    var def swap_entries(a: Int, b: Int) -> Unit:
        self.heap.swap(a, b)
        self.orders.swap(a, b)

    # Moves the entry at `start` up, but no higher than `floor`, while it dequeues before its parent.
    var def sift_up(start: Int, floor: Int) -> Unit:
        var at = start

        while at > floor:
            let parent = (at - 1) / 2
            if not self.before(at, parent):
                break

            self.swap_entries(at, parent)
            at = parent

    # Moves the entry at `start` down the path of earlier children to the bottom, then back up to where it belongs:
    # one comparison per level on the way down instead of two, since a displaced last entry usually belongs near the bottom.
    var def sift_down(start: Int) -> Unit:
        let size = self.heap.length()
        var at = start

        while True:
            var child = at * 2 + 1
            if child >= size:
                break

            if child + 1 < size and self.before(child + 1, child):
                child += 1
            self.swap_entries(child, at)
            at = child

        self.sift_up(at, start)

    # Adds a value, returning False when a bounded queue is full. A non-positive capacity faults.
    var def enqueue(value: T) -> Bool:
        if let limit = self.capacity:
            if limit <= 0:
                panic(
                    f"PriorityQueue: capacity must be between 1 and 9223372036854775807, found {limit}"
                )
            if self.heap.length() >= limit:
                return False

        self.heap.append(value)
        self.orders.append(self.next_order)
        self.next_order += 1
        self.sift_up(self.heap.length() - 1, 0)
        return True

    # Removes and returns the next value by priority, or `none` when empty.
    var def dequeue() -> Optional[T]:
        let count = self.heap.length()
        if count == 0:
            return none

        self.swap_entries(0, count - 1)
        self.orders.pop()

        let top = self.heap.pop()
        self.sift_down(0)
        return top

    # Returns the next value by priority without removing it, or none when empty.
    def peek() -> Optional[T]:
        if self.heap.length() == 0:
            return none

        return self.heap.get(0).clone()

    # Returns the number of enqueued values, independent of their priorities.
    def length() -> Int:
        return self.heap.length()

    # Reports whether the queue has no values to peek or dequeue.
    def is_empty() -> Bool:
        return self.heap.length() == 0

# Creates a PriorityQueue that dequeues the smallest value first, using the value type's `Comparable` order.
# Example: `ordered_priority_queue[Int]()` dequeues 1 before 2; pass `capacity` to bound it.
export def ordered_priority_queue[T: Comparable & Clonable](
    capacity: Optional[Int] = none
) -> PriorityQueue[T]:
    return PriorityQueue[T](compare: lambda a, b: a.compare(b), capacity: capacity)
