# HIR to MIR lowering

`ms-lower` turns a checked program (`ms-check`'s HIR query view) into monomorphic MIR for `ms-mir`, which `ms-clif` compiles. The gate is `ms-conform` running tier-core fixtures through a native build, compared with the Go `ms` as oracle.

```
make build && cargo build -p ms-lower -p ms-rt -p ms-conform
target/debug/ms-conform run --ms target/debug/msl --tag tier-core --phase run
target/debug/msl run FILE        # also: build FILE -o OUT, --dump-mir, --no-opt
```

## Strategy

- **Instances.** Every source callable is lowered once per substitution of its type variables (`Cx::function_for`); bodies are queued and lowered on demand from `main`.
- **Ownership (v1).** Locals are SSA variables; a type that needs drop is `Own`. Reading a local in an owning position copies it, owned temporaries used only as borrows are dropped at statement end, scopes drop their locals on every exit (return, break, continue). Parameters are `Borrow`. Last-use moves replace copies later.
- **Defaults** are evaluated by the caller in the callee's module context.
- **Natives** become runtime calls (`native.rs`: `PLAIN_STRING`, descriptor-based list calls) or short MIR sequences (`list.reversed`, `get` with default). `stdout()`/`stderr()` are interface values over MIR-built vtables.
- **Text forms** (`to_string`, interpolation) are generated per type as helper functions (`text.rs`).

## Not yet lowered

Closures and function values, `match`, `try`, `with`, destructuring, Map/Set literals and natives, record/alternative text forms, aggregate equality, `var` parameters, and the remaining native methods. The lowerer reports each as `unsupported ...`; the conformance run lists what still fails.
