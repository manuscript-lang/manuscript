+++
title = "errors"
+++

# @std/errors.ms

Import each required symbol with `import Name from "@std/errors.ms"`.

## Error

Kind: interface.

```text
Error: Error
operation message: fn()->String
```

## as_error

Kind: fn.

```text
as_error: fn(cause: E)->Error
type parameters: E: Error
```

