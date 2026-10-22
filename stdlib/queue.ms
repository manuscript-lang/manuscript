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
