+++
title = "queues"
+++

# @std/queues.ms

Import each required symbol with `import Name from "@std/queues.ms"`.

## PriorityQueue {data-api-kind="Native type"}

```manuscript
type PriorityQueue[T]:
    compare: fn(left: T, right: T) -> Int
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool:
    fn dequeue() -> Optional[T]:
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:
```

## Queue {data-api-kind="Native type"}

```manuscript
type Queue[T]:
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool:
    fn dequeue() -> Optional[T]:
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:
```

