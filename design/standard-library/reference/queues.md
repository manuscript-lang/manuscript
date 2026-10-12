+++
title = "queues"
+++

# @std/queues.ms

Import each required symbol with `import Name from "@std/queues.ms"`.

## Queue {data-api-kind="Interface"}

```manuscript
Queue: Queue[T]
type parameters: T
field capacity: Int
operation dequeue: fn()->Optional[T]
operation enqueue: fn(value: T)->Bool
operation is_empty: fn()->Bool
operation length: fn()->Int
operation peek: fn()->Optional[T]
```

