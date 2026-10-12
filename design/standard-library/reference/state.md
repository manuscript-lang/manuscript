+++
title = "state"
+++

# @std/state.ms

Import each required symbol with `import Name from "@std/state.ms"`.

## State

Kind: interface.

```manuscript
State: State[T]
type parameters: T: Shareable
field value: T
operation get: fn()->T
operation set: fn(value: T)->Unit
operation swap: fn(value: T)->T
```

