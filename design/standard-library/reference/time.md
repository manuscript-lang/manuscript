+++
title = "time"
+++

# @std/time.ms

Import each required symbol with `import Name from "@std/time.ms"`.

## Clock

Kind: contract.

```text
Clock: Clock
operation now: fn()->Instant
```

## Duration

Kind: native.

```text
Duration: Duration
```

## Instant

Kind: native.

```text
Instant: Instant
```

## sleep

Kind: fn.

```text
sleep: fn(duration: Duration)->Unit
```

