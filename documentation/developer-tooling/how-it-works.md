+++
title = "How it works"
weight = 0
+++

# How it works

`ms` is one self-contained binary. It checks your program and compiles it to a native executable. Cranelift and the compiled runtime are embedded, and Linux release builds optimize with LLVM when `clang` is installed; linking requires host tools ([requirements](../contributing/rust-toolchain.md#differences-users-can-see)).

```text
.ms source → parse → check (HIR) → lower (MIR) → Cranelift or LLVM object code → link → executable
```

1. **Parse and check.** Resolves imports, then checks types, control flow, cleanup, and effects. Errors stop here.
2. **Lower and compile.** Checked HIR becomes MIR, which is optimized and verified before Cranelift (or LLVM, for Linux release builds) emits object code. `ms emit` prints MIR for inspection.
3. **Link.** The host compiler driver links the object with the embedded runtime and native standard library. `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

## One binary

`ms` also includes the formatter, linter, language server (`ms lsp`), and profiling commands (`ms profile`). The standard library matches your `ms` version. Nothing is downloaded at build time.

## Runtime cache

The embedded runtime archive is extracted once and reused by later links. Executables are rebuilt each time; see [build caches](builds/incremental-compilation.md) for locations and overrides.

## Where to go next

- [Build levels](builds/build-levels.md)
- [Build caches](builds/incremental-compilation.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
