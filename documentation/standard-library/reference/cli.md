+++
title = "cli"
+++

# @std/cli.ms

Import each required symbol with `import Name from "@std/cli.ms"`.

## arguments {data-api-kind="Function"}

Returns process arguments, excluding the executable path.

```manuscript
fn arguments() -> List[String]:
```

## environment {data-api-kind="Function"}

Returns the process environment as a map of variable names to values.

```manuscript
fn environment() -> Map[String, String]:
```

