# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

export type Queue[T]:
    # Optional constructor argument; omit for an unbounded queue.
    capacity: Int
    fn enqueue(value: T) -> Bool
    fn dequeue() -> Optional[T]
    fn peek() -> Optional[T]
    fn length() -> Int
    fn is_empty() -> Bool
