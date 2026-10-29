import {Iterator, panic} from "@std/core.ms"
import Iterable from "@std/iterable.ms"

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
    # Adds a value, returning False when a bounded queue is full. A non-positive capacity faults.
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
            for index in self.head..count:
                live.append(self.items.replace(index, none))
            self.items = live
            self.head = 0

        self.items.append(value)
        return true

    # Removes and returns the oldest value, or `none` when empty.
    var fn dequeue() Optional[T]:
        if self.head >= self.items.length():
            return none

        let value = self.items.replace(self.head, none)
        self.head += 1

        if self.head == self.items.length():
            self.items = []
            self.head = 0

        return value

    # Returns the oldest value without removing it, or none when the queue is empty.
    fn peek() ref Optional[T]:
        if self.head >= self.items.length():
            return none

        return self.items.get(self.head)

    # Reports whether dequeue and peek would return none.
    fn is_empty() Bool:
        return self.head >= self.items.length()

impl Queue[T]:
    # Returns the number of values currently waiting in the queue.
    fn length() Int:
        return self.items.length() - self.head

    # Returns the value `index` places after the oldest, or none when out of range; negative indexes are out of range.
    fn at(index: Int) ref Optional[T]:
        if index < 0 or index >= self.length():
            return none

        return self.items.get(self.head + index)

# Walks a queue from the oldest value to the newest, lending each value; made by `iter()` and used by `for`.
export type QueueIter[T]:
    # The queue being walked.
    source: ref Queue[T]
    # Distance from the oldest value of the value `next` returns.
    position: Int

impl Iterator[T] for QueueIter[T]:
    # Returns the value at the current position and moves past it, or none after the newest.
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        if item.is_none():
            return none

        self.position += 1
        return item

impl Iterable[QueueIter[T]] for Queue[T]:
    # Returns an iterator over the values from oldest to newest, borrowing the queue.
    fn iter() QueueIter[T]:
        return QueueIter(source: self, position: 0)

# Orders two values: negative when `left` dequeues first, zero when equal, positive when `right` dequeues first.
fn order[T: Comparable](left: T, right: T) Int:
    return left.compare(right)

# Values dequeue in their `Comparable` order, smallest first; equal priorities remain FIFO. Wrap a value in a record with `impl Comparable` to order by anything else.
# A priority queue is an owned value: a copy is an independent queue.
export type PriorityQueue[T: Comparable]:
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
    fn before(a: Int, b: Int) Bool:
        let order = order(self.heap.get(a), self.heap.get(b))
        return order < 0 or (order == 0 and self.orders.get(a) < self.orders.get(b))

    # Exchanges the heap entries at `a` and `b`.
    var fn swap_entries(a: Int, b: Int) Unit:
        self.heap.swap(a, b)
        self.orders.swap(a, b)

    # Moves the entry at `start` up, but no higher than `floor`, while it dequeues before its parent.
    var fn sift_up(start: Int, floor: Int) Unit:
        var at = start

        while at > floor:
            let parent = (at - 1) / 2
            if not self.before(at, parent):
                break

            self.swap_entries(at, parent)
            at = parent

    # Moves the entry at `start` down the path of earlier children to the bottom, then back up to where it belongs:
    # one comparison per level on the way down instead of two, since a displaced last entry usually belongs near the bottom.
    # The loop runs while the entry has a left child, and the guards on `at` let the compiler prove every index in range.
    var fn sift_down(start: Int) Unit:
        let size = self.heap.length()
        let parents = size / 2
        var at = start

        while at >= 0 and at < parents:
            let left = at * 2 + 1
            let right = left + 1

            if right < size and self.before(right, left):
                self.swap_entries(right, at)
                at = right
            else:
                self.swap_entries(left, at)
                at = left

        self.sift_up(at, start)

    # Adds a value, returning False when a bounded queue is full. A non-positive capacity faults.
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
        self.sift_up(self.heap.length() - 1, 0)
        return true

    # Removes and returns the next value by priority, or `none` when empty.
    var fn dequeue() Optional[T]:
        let count = self.heap.length()
        if count == 0:
            return none

        self.swap_entries(0, count - 1)
        self.orders.pop()

        let top = self.heap.pop()
        self.sift_down(0)
        return top

    # Returns the next value by priority without removing it, or none when empty.
    fn peek() ref Optional[T]:
        if self.heap.length() == 0:
            return none

        return some(self.heap.get(0))

    # Reports whether the queue has no values to peek or dequeue.
    fn is_empty() Bool:
        return self.heap.length() == 0

impl PriorityQueue[T]:
    # Returns the number of enqueued values, independent of their priorities.
    fn length() Int:
        return self.heap.length()

    # Returns the value at `index` in heap order, or none when out of range; only index 0 is known to be the next to dequeue.
    # Negative indexes are out of range.
    fn at(index: Int) ref Optional[T]:
        if index < 0 or index >= self.heap.length():
            return none

        return some(self.heap.get(index))

# Walks a priority queue in heap order, lending each value; made by `iter()` and used by `for`.
export type PriorityQueueIter[T: Comparable]:
    # The queue being walked.
    source: ref PriorityQueue[T]
    # Heap index of the value `next` returns.
    position: Int

impl Iterator[T] for PriorityQueueIter[T]:
    # Returns the value at the current heap position and moves past it, or none after the last.
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        if item.is_none():
            return none

        self.position += 1
        return item

impl Iterable[PriorityQueueIter[T]] for PriorityQueue[T]:
    # Returns an iterator over the values in heap order, borrowing the queue; only the first is known to be the next to dequeue.
    fn iter() PriorityQueueIter[T]:
        return PriorityQueueIter(source: self, position: 0)
