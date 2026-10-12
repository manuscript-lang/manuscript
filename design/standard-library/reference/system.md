+++
title = "system"
+++

# @std/system.ms

Import each required symbol with `import Name from "@std/system.ms"`.

## System {data-api-kind="Interface"}

```manuscript
System: System
operation environment: fn(name: String)->Optional[String]
operation info: fn()->SystemInfo
operation working_directory: fn()->String
```

## SystemInfo {data-api-kind="Record"}

```manuscript
SystemInfo: SystemInfo
field os: String
field architecture: String
field cpu_count: Int
```

