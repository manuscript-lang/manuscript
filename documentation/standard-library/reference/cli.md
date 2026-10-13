+++
title = "cli"
+++

# @std/cli.ms

Import each required symbol with `import Name from "@std/cli.ms"`.

## arguments {data-api-kind="Function"}

Returns the host-supplied startup arguments, excluding the executable path.
Repeated calls share the same mutable list; mutations do not rewrite native argv.

```manuscript
fn arguments() -> List[String]:
```

## environment {data-api-kind="Function"}

Returns the startup environment snapshot, not the live process environment.
Repeated calls share the same mutable map; mutations do not call set_environment.

```manuscript
fn environment() -> Map[String, String]:
```

