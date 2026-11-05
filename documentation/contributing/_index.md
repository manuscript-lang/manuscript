+++
title = "Contributing"
weight = 6
+++

# Contributing

Build and run the checkout before changing it (repository root).

```sh
make build
target/release/ms run examples/hello/ms.toml -- first second
```

The program prints:

```text
Arguments: 2
```

- Alpha: syntax and APIs may change.
- Keep a regression for each changed behavior.


Next: [architecture](architecture.md) and [contribution rules](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md).
