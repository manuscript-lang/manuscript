# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

# FIFO queue. An omitted capacity creates an unbounded queue.
export type Queue[T]:
    # Optional constructor argument; omit for an unbounded queue.
    capacity: Optional[Int] = none
    # Adds a value, returning false when a bounded queue is full.
    fn enqueue(value: T) -> Bool:
    # Removes and returns the oldest value, or `none` when empty.
    fn dequeue() -> Optional[T]:
    # Returns the oldest value without removing it.
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:

# Negative compare results put left before right; equal priorities remain FIFO.
export type PriorityQueue[T]:
    compare: fn(left: T, right: T) -> Int
    capacity: Optional[Int] = none
    # Adds a value, returning false when a bounded queue is full.
    fn enqueue(value: T) -> Bool:
    # Removes and returns the next value by priority, or `none` when empty.
    fn dequeue() -> Optional[T]:
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:
