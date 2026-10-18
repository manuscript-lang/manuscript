# A local mutable FIFO queue; protect all shared access with Synchronized.
# Omitted or none capacity grows as needed and adds no fixed queue limit.
export type Queue[T]:
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none

impl Queue[T]:
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

# A FIFO queue that waits instead of failing: put blocks while a bounded queue is full,
# and take blocks while the queue is empty. It synchronizes itself, so tasks share it directly.
# Waiting stops at cancellation, so a TaskGroup close unblocks every waiting task.
#
# Usage: create it with `BlockingQueue[Int](8)` (omit capacity for an unbounded queue), start workers in a
# TaskGroup that loop on `jobs.take()` until it returns none, then call `jobs.put(value)` to hand them work
# (it waits while full and returns false once closed) and `jobs.close()` when done; workers drain the queued
# values and then see none.
export type BlockingQueue[T]:
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none

impl BlockingQueue[T]:
    # Waits for free space, then adds the value and returns true. Returns false when the queue is closed.
    fn put(value: T) -> Bool:

    # Waits for a value and removes the oldest. Returns none once the queue is closed and empty.
    fn take() -> Optional[T]:

    # Closes the queue and wakes every waiting task. Queued values can still be taken; later puts return false.
    fn close() -> Unit:

    # Returns the number of values currently waiting in the queue.
    fn length() -> Int:

    # Reports whether close has been called.
    fn is_closed() -> Bool:

# Negative compare results put left before right; equal priorities remain FIFO.
export type PriorityQueue[T]:
    # Constructor comparator: negative puts left first; ties dequeue in enqueue order.
    # Comparisons must stay consistent and must not mutate this queue.
    compare: fn(left: T, right: T) -> Int
    # Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.
    capacity: Optional[Int] = none

impl PriorityQueue[T]:
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
