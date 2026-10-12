+++
title = "tasks"
+++

# @std/tasks.ms

Import each required symbol with `import Name from "@std/tasks.ms"`.

## Background {data-api-kind="Native type"}

```manuscript
type Background:
    fn cancel(id: OperationId) -> Unit
    fn close() -> Unit
    fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]
    fn status(id: OperationId) -> WorkStatus
```

## BackgroundFailure {data-api-kind="Alternative"}

```manuscript
type BackgroundFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)
```

## ExecutionError {data-api-kind="Alternative"}

```manuscript
type ExecutionError:
    case TimedOut
    case Crashed(operation: OperationId, message: String)
```

```manuscript
impl Error for ExecutionError:
    fn message() -> String
```

## OperationId {data-api-kind="Native type"}

```manuscript
type OperationId
```

## StartError {data-api-kind="Alternative"}

```manuscript
type StartError:
    case Closed
    case Full
```

```manuscript
impl Error for StartError:
    fn message() -> String
```

## WorkStatus {data-api-kind="Alternative"}

```manuscript
type WorkStatus:
    case Running
    case Succeeded
    case Failed
    case Cancelled
    case Crashed
    case Unknown
```

## check_cancelled {data-api-kind="Function"}

```manuscript
fn check_cancelled() -> Unit
```

## parallel {data-api-kind="Function"}

See [special call rules](../call-rules.md).

