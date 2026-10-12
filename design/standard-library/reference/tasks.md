+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## Background {data-api-kind="Interface"}

```manuscript
Background: Background
operation cancel: fn(id: OperationId)->Unit
operation close: fn()->Unit
operation start: fn(operation: fn()->Result[Unit, String])->Result[OperationId, StartError]
operation status: fn(id: OperationId)->WorkStatus
```

## BackgroundFailure {data-api-kind="Alternative"}

```manuscript
BackgroundFailure: BackgroundFailure
case Failed(operation: OperationId, cause: String)
case Crashed(operation: OperationId, message: String)
```

## ExecutionError {data-api-kind="Alternative"}

```manuscript
ExecutionError: ExecutionError
case TimedOut
case Crashed(operation: OperationId, message: String)
```

## OperationId {data-api-kind="Native type"}

```manuscript
OperationId: OperationId
```

## StartError {data-api-kind="Alternative"}

```manuscript
StartError: StartError
case Closed
case Full
```

## WorkStatus {data-api-kind="Alternative"}

```manuscript
WorkStatus: WorkStatus
case Running
case Succeeded
case Failed
case Cancelled
case Crashed
case Unknown
```

## check_cancelled {data-api-kind="Function"}

```manuscript
check_cancelled: fn()->Unit
```

## parallel {data-api-kind="Function"}

```manuscript
parallel: fn()-><unknown>
```

## parallel_map {data-api-kind="Function"}

```manuscript
parallel_map: fn(items: List[T], operation: fn(item: T)->U, limit: Int)->Result[List[U], ExecutionError]
type parameters: T, U
```

