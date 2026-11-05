+++
title = "Compiler internals"
weight = 4
+++

# Compiler internals

Compare checking with execution to locate a failure in an agent’s compiler change (repository root).

```sh
target/release/ms check examples/hello/ms.toml
target/release/ms run examples/hello/ms.toml -- first second
```

```text
Checked examples/hello/ms.toml (2 modules)
Arguments: 2
```

- Check failures precede lowering; wrong results also need runtime investigation.
- Alpha: reproduce against the current checkout.


Next: [pipeline](pipeline.md), [frontend](frontend/_index.md), [lowering](lowering/_index.md), and [conformance](conformance/_index.md).
