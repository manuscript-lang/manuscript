+++
title = "Parsing and checking"
weight = 1
+++

# Parsing and checking

Check the example with the built compiler (repository root).

```sh
target/release/ms check examples/hello/ms.toml
```

```text
Checked examples/hello/ms.toml (2 modules)
```

- Checking resolves source rules without linking or execution.
- Alpha: retain acceptance and rejection regressions.


Next: [pipeline](pipeline.md), [types](type-checker.md), [captures](scope-checker.md), and [HIR](typed-ir.md).
