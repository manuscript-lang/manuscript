# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

export type Queue[T]:
    # Optional constructor argument; omit for an unbounded queue.
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool
    fn dequeue() -> Optional[T]
    fn peek() -> Optional[T]
    fn length() -> Int
    fn is_empty() -> Bool

# Negative compare results put left before right; equal priorities remain FIFO.
export type PriorityQueue[T]:
    compare: fn(left: T, right: T) -> Int
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool
    fn dequeue() -> Optional[T]
    fn peek() -> Optional[T]
    fn length() -> Int
    fn is_empty() -> Bool
