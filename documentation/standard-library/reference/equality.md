+++
title = "equality"
+++

# @std/equality.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/equality.ms"` remain supported.

## Equal {data-api-kind="Interface"}

Equality and hashing are ordinary operation interfaces. Built-in data retains
its value semantics; an explicit implementation selects domain identity.

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool
```

### Equal.equals

Compares this value with another value in the same domain.

```manuscript
fn equals(other: Equal) -> Bool
```

## Hashable {data-api-kind="Interface"}

A type with a stable hash consistent with its `Equal` implementation.

```manuscript
interface Hashable:
    fn hash() -> Int
```

### Hashable.hash

Returns a stable hash consistent with `equals` for the same value.

```manuscript
fn hash() -> Int
```

