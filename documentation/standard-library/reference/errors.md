+++
title = "errors"
+++

# @std/errors.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/errors.ms"` remain supported.

## Error {data-api-kind="Interface"}

A contract for expected failures that can provide a human-readable message.

```manuscript
interface Error:
    fn message() -> String
```

### Error.message

Returns a human-readable description of this expected error.

```manuscript
fn message() -> String
```

## ErrorCategory {data-api-kind="Alternative"}

Portable categories for shared standard error cases. Domain errors retain their types and payloads.

```manuscript
type ErrorCategory:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case Unavailable
```

### ErrorCategory.AlreadyExists

A requested exclusive resource already exists.

```manuscript
case AlreadyExists
```

### ErrorCategory.Closed

The resource has been closed.

```manuscript
case Closed
```

### ErrorCategory.InvalidData

Input data is malformed.

```manuscript
case InvalidData
```

### ErrorCategory.InvalidInput

Caller input is invalid.

```manuscript
case InvalidInput
```

### ErrorCategory.LimitExceeded

An operation budget or implementation limit was exceeded.

```manuscript
case LimitExceeded
```

### ErrorCategory.NotFound

A requested resource was not found.

```manuscript
case NotFound
```

### ErrorCategory.PermissionDenied

Host authority denied the operation.

```manuscript
case PermissionDenied
```

### ErrorCategory.Timeout

A local operation or group deadline expired.

```manuscript
case Timeout
```

### ErrorCategory.Unavailable

The service/resource is unavailable; this does not imply NotFound or PermissionDenied.

```manuscript
case Unavailable
```

### ErrorCategory.Unsupported

The requested operation is unsupported.

```manuscript
case Unsupported
```

## TextError {data-api-kind="Alternative"}

An error that carries only intentional text, for callers that have no domain error to return.

```manuscript
type TextError:
    case Text(message: String)
```

```manuscript
impl Error for TextError:
    fn message() -> String:
```

### TextError.Text

Wraps the human-readable description returned by message().

```manuscript
case Text(message: String)
```

### TextError.Text.message

Description returned verbatim by message().

```manuscript
message: String
```

### TextError.Error.message

Returns the wrapped text verbatim.

```manuscript
fn message() -> String:
```

## category {data-api-kind="Function"}

Queries a shared category without changing or invoking the error.
Recognized standard cases use their same-name category.
Custom errors and domain-specific cases (including Failed, Full, OutputLimit, OutOfRange,
AuthenticationFailed and wrapped LogError causes) return none. Messages are never parsed.

```manuscript
fn category(cause: Error) -> Optional[ErrorCategory]:
```

