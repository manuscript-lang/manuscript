+++
title = "How it works"
weight = 0
+++

# How it works

`ms` checks your program and compiles it to a native executable. The compiler, Cranelift backend, runtime and standard library ship together. Native linking and LLVM optimization use pinned tools downloaded on first use and cached for later builds; a fresh installation needs network access. See [toolchain requirements](../contributing/rust-toolchain.md#differences-users-can-see) for local-tool overrides and platform details.

```text
.ms source → parse → check (HIR) → lower (MIR) → Cranelift or LLVM object code → link → executable
```

1. **Parse and check.** Resolves imports, then checks types, control flow, cleanup, and effects. Errors stop here.
2. **Lower and compile.** Checked HIR becomes MIR, which is optimized and verified before Cranelift or LLVM emits object code. Debug uses Cranelift; Release and MinSizeRel use LLVM when available, falling back to Cranelift if the LLVM tools cannot be fetched. `ms emit` prints MIR for inspection.
3. **Link.** The pinned `lld` links the object with the embedded runtime and native standard library. `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

## One binary

`ms` also includes the formatter, linter, language server (`ms lsp`), and profiling commands (`ms profile`). The standard library matches your `ms` version. Source-only commands such as `check`, `fmt` and `lint` do not need native linking tools. The first native link downloads `lld`; the first optimized build also fetches the LLVM tools. Downloads are checked against pinned SHA-256 hashes. Set `MS_LLD` to a local linker and `MS_LLVM_TOOLS` to a local LLVM tools directory to provision these ahead of time; `MS_BACKEND=cranelift` skips LLVM optimization but still needs a linker.

## Runtime cache

The embedded runtime archive is extracted once and reused by later links. Executables are rebuilt each time; see [build caches](builds/incremental-compilation.md) for locations and overrides.

## Where to go next

- [Build levels](builds/build-levels.md)
- [Build caches](builds/incremental-compilation.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
