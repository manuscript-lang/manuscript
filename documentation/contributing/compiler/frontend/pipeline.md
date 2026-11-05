+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

Separate checking failures from execution failures when reviewing an agent’s pipeline change (repository root).

```sh
target/release/ms check examples/hello/ms.toml
target/release/ms run examples/hello/ms.toml -- first second
```

```text
Checked examples/hello/ms.toml (2 modules)
Arguments: 2
```

- Checking records types and ownership; native compilation consumes those facts.
- Alpha: compiler stages may change.


Next: [pass responsibilities](../pipeline.md) and [project inputs](../../../developer-tooling/builds/project-configuration.md).
