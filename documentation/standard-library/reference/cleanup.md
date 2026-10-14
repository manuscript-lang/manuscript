+++
title = "cleanup"
+++

# @std/cleanup.ms

Import each required symbol with `import Name from "@std/cleanup.ms"`.

## Closeable {data-api-kind="Interface"}

A resource that can be closed. `with` closes a bound resource on every exit.

```manuscript
interface Closeable:
    fn close() -> Unit
```

### Closeable.close

Releases the implementation's resource state; with calls this on every scope exit.
Cleanup runs during return, expected errors, faults, and cancellation too.

```manuscript
fn close() -> Unit
```

