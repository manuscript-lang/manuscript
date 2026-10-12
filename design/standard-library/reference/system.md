+++
title = "system"
+++

# @std/system.ms

Import each required symbol with `import Name from "@std/system.ms"`.

## System {data-api-kind="Interface"}

```manuscript
interface System:
    fn environment(name: String) -> Optional[String]
    fn info() -> SystemInfo
    fn working_directory() -> String
```

## SystemInfo {data-api-kind="Record"}

```manuscript
type SystemInfo:
    os: String
    architecture: String
    cpu_count: Int
```

