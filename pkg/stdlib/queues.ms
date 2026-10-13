# Canonical standard-library declarations. Implementations are native.

# A local mutable FIFO queue; protect all shared access with Synchronized.
# Omitted or none capacity grows as needed and adds no fixed queue limit.
export type Queue[T]:
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Adds a value, returning false when a bounded queue is full.
    fn enqueue(value: T) -> Bool:
    # Removes and returns the oldest value, or `none` when empty.
    fn dequeue() -> Optional[T]:
    # Returns the oldest value without removing it, or none when the queue is empty.
    fn peek() -> Optional[T]:
    # Returns the number of values currently waiting in the queue.
    fn length() -> Int:
    # Reports whether dequeue and peek would return none.
    fn is_empty() -> Bool:

# Negative compare results put left before right; equal priorities remain FIFO.
export type PriorityQueue[T]:
    # Constructor comparator: negative puts left first; ties dequeue in enqueue order.
    # Comparisons must stay consistent and must not mutate this queue.
    compare: fn(left: T, right: T) -> Int
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none
    # Adds a value, returning false when a bounded queue is full.
    fn enqueue(value: T) -> Bool:
    # Removes and returns the next value by priority, or `none` when empty.
    fn dequeue() -> Optional[T]:
    # Returns the next value by priority without removing it, or none when empty.
    fn peek() -> Optional[T]:
    # Returns the number of enqueued values, independent of their priorities.
    fn length() -> Int:
    # Reports whether the queue has no values to peek or dequeue.
    fn is_empty() -> Bool:
