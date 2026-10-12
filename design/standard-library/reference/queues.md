+++
title = "queues"
+++

# @std/queues.ms

Import each required symbol with `import Name from "@std/queues.ms"`.

## Queue

Kind: interface.

```text
Queue: Queue[T]
type parameters: T
field capacity: Int
operation close: fn()->Unit
operation receive: fn()->Optional[T]
operation send: fn(value: T)->Result[Unit, QueueError]
```

## QueueError

Kind: alternative.

```text
QueueError: QueueError
case Closed
```

