+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## Background

Kind: interface.

```manuscript
Background: Background
operation cancel: fn(id: OperationId)->Unit
operation close: fn()->Unit
operation start: fn(operation: fn()->Result[Unit, String])->Result[OperationId, StartError]
operation status: fn(id: OperationId)->WorkStatus
```

## BackgroundFailure

Kind: alternative.

```manuscript
BackgroundFailure: BackgroundFailure
case Failed(operation: OperationId, cause: String)
case Crashed(operation: OperationId, message: String)
```

## ExecutionError

Kind: alternative.

```manuscript
ExecutionError: ExecutionError
case TimedOut
case Crashed(operation: OperationId, message: String)
```

## OperationId

Kind: native.

```manuscript
OperationId: OperationId
```

## StartError

Kind: alternative.

```manuscript
StartError: StartError
case Closed
case Full
```

## WorkStatus

Kind: alternative.

```manuscript
WorkStatus: WorkStatus
case Running
case Succeeded
case Failed
case Cancelled
case Crashed
case Unknown
```

## check_cancelled

Kind: fn.

```manuscript
check_cancelled: fn()->Unit
```

## parallel

Kind: fn.

```manuscript
parallel: fn()-><unknown>
```

## parallel_map

Kind: fn.

```manuscript
parallel_map: fn(items: List[T], operation: fn(item: T)->U, limit: Int)->Result[List[U], ExecutionError]
type parameters: T, U
```

