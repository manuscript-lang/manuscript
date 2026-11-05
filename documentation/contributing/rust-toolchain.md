+++
title = "Rust toolchain"
weight = 4
+++

# Rust toolchain

Build the compiler and its runtime from the repository root.

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

The program prints:

```text
Arguments: 2
```

- Use pinned Rust, Make and a C compiler; cache or fetch setup dependencies.
- Alpha: rebuild the runtime after native changes.

<span id="build-and-run"></span>
<span id="build-cache-and-metadata"></span>
<span id="checks"></span>
<span id="crates"></span>
<span id="differences-users-can-see"></span>
<span id="optimization"></span>
<span id="platform-linking"></span>
<span id="runtime-and-platform-behavior"></span>
<span id="source-attribution-and-inspection"></span>

Next: [checks](development.md), [platform linking](../developer-tooling/builds/build-levels.md), [local tools](../developer-tooling/how-it-works.md#build-tools-and-local-setup), and [Windows setup](https://github.com/manuscript-lang/manuscript/blob/main/toolchain/fetch-mingw.sh).
