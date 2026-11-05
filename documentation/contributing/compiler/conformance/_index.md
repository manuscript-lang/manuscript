+++
title = "Compiler conformance"
weight = 3
+++

# Compiler conformance

Run the example’s behavioral assertions (repository root).

```sh
target/release/ms test examples/hello/ms.toml
```

```text
RUN test.ms::getting started
PASS test.ms::getting started
1 tests, 0 failed
```

- Use executable assertions for runtime behavior and rejection fixtures for invalid source.
- Alpha: reconcile regressions with current rules.


Next: [semantic tests](semantic-tests.md) and [check targets](../../development.md).
