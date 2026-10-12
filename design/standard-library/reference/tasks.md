+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## Background

Kind: interface.

```text
Background: Background
operation cancel: fn(id: OperationId)->Unit
operation close: fn()->Unit
operation start: fn(operation: fn()->Result[Unit, String])->Result[OperationId, StartError]
operation status: fn(id: OperationId)->WorkStatus
```

## BackgroundFailure

Kind: alternative.

```text
BackgroundFailure: BackgroundFailure
case Failed(operation: OperationId, cause: String)
case Crashed(operation: OperationId, message: String)
```

## ExecutionError

Kind: alternative.

```text
ExecutionError: ExecutionError
case TimedOut
case Crashed(operation: OperationId, message: String)
```

## OperationId

Kind: native.

```text
OperationId: OperationId
```

## StartError

Kind: alternative.

```text
StartError: StartError
case Closed
case Full
```

## WorkStatus

Kind: alternative.

```text
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

```text
check_cancelled: fn()->Unit
```

## parallel

Kind: fn.

```text
parallel: fn()-><unknown>
```

## parallel_map

Kind: fn.

```text
parallel_map: fn(items: List[T], operation: fn(item: T)->U, limit: Int)->Result[List[U], ExecutionError]
type parameters: T, U
```

