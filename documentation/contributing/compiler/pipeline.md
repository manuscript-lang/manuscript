+++
title = "Pipeline and passes"
weight = 0
+++

# Pipeline and passes

Emit MIR to investigate a checked program’s generated behavior (repository root).

```sh
target/release/ms emit examples/hello/ms.toml -o hello.mir
head -n 5 hello.mir
```

```text
module "main"
file 0 "src/main.ms"
file 1 "@std/io/io.ms"
file 2 "@std/concurrency/promise.ms"
file 3 "@std/os/process.ms"
```

- Emission writes `hello.mir`; the excerpt locates source files.
- MIR is internal notation; alpha representations may change.

<span id="adding-a-pass"></span>
<span id="checking-each-module-once"></span>
<span id="passes"></span>

Next: [pass responsibilities](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) and [evaluation order](lowering/evaluation-order.md).
