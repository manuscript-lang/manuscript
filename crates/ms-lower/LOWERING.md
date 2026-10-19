# HIR to MIR lowering

`ms-lower` turns a checked program (`ms-check`'s HIR query view) into monomorphic MIR for `ms-mir`, which `ms-clif` compiles. The gate is `ms-conform` running tier-core fixtures through a native build, compared with the Go `ms` as oracle.

```
make build && cargo build -p ms-lower -p ms-native -p ms-conform
target/debug/ms-conform run --ms target/debug/msl --tag tier-core --phase run
target/debug/msl run FILE        # also: build FILE -o OUT, --dump-mir, --no-opt
target/debug/msl test FILE --json # one process per test; the report matches `ms test --json`
```

## Strategy

- **Instances.** Every source callable is lowered once per substitution of its type variables (`Cx::function_for`); bodies are queued and lowered on demand from `main`.
- **Ownership (v1).** Locals are SSA variables; a type that needs drop is `Own`. Reading a local in an owning position copies it, owned temporaries used only as borrows are dropped at statement end, scopes drop their locals on every exit (return, break, continue). Parameters are `Borrow`. Last-use moves replace copies later.
- **Defaults** are evaluated by the caller in the callee's module context.
- **Natives** become runtime calls (`native.rs`: `PLAIN_STRING`, descriptor-based list calls) or short MIR sequences (`list.reversed`, `get` with default). `stdout()`/`stderr()` are interface values over MIR-built vtables.
- **Runtime calls** that follow the ABI conventions (`rtcall.rs`) are marshalled from the symbol's declared signature in `ms-rt/SYMBOLS.md`: descriptors, flattened optionals, `out` pointers and `u8` statuses become `Result`/`Optional` values.
- **Text forms** (`to_string`, interpolation, and the quoted form test failures print) and **structural equality** are generated per type as helper functions (`text.rs`, `eq.rs`).
- **Interfaces.** `Iface(value: x)` and the checker's Error-boundary conversions build an interface value over a vtable of wrappers that call the source methods (`iface.rs`); standard errors with native `message()` have tables there.
- **Tests.** `lower_tests` lowers every `test` block and a runner entry that runs test `i` for argument `i`; a failure writes a marked message to stderr (`runner.rs`, `pipeline::test`).

## Not yet lowered

`with`, destructuring, Map/Set literals and natives, `expect_fault` and `skip` (they need a catchable fault in the runtime), test fixtures and hooks, `Bytes` text forms, and the remaining native methods. The lowerer reports each as `unsupported ...`; the conformance run lists what still fails. Fixtures that mutate through non-`var` methods rely on reference semantics and differ by design (value semantics, `design-contract.md`).
