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
operation close: fn()->Unit
operation receive: fn()->Optional[T]
operation send: fn(value: T)->Result[Unit, QueueError]
```

## QueueError {data-api-kind="Alternative"}

```manuscript
QueueError: QueueError
case Closed
```

