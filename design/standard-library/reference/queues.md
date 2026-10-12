+++
title = "queues"
+++

# @std/queues.ms

Import each required symbol with `import Name from "@std/queues.ms"`.

## Queue {data-api-kind="Native type"}

```manuscript
type Queue[T]:
    capacity: Int
    fn enqueue(value: T) -> Bool
    fn dequeue() -> Optional[T]
    fn peek() -> Optional[T]
    fn length() -> Int
    fn is_empty() -> Bool
```

