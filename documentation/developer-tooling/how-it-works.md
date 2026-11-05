+++
title = "How it works"
weight = 0
+++

# How it works

`ms` checks your program and compiles it ahead of time to a native executable. The compiler, Cranelift backend, runtime and standard library ship together. The resulting executable runs directly on its target platform.

```text
.ms source → parse → check (HIR) → lower (MIR) → Cranelift or LLVM object code → link → executable
```

1. **Parse and check.** Resolves imports, then checks types, control flow, cleanup, and effects. Errors stop here.
2. **Lower and compile.** Checked HIR becomes MIR, which is optimized and verified before Cranelift or LLVM emits object code. Debug uses Cranelift to keep compilation fast for quick iteration. Release uses LLVM to optimize runtime performance, and MinSizeRel favors code size as well. Both use Cranelift if the LLVM tools are unavailable or cannot be fetched. `ms emit` prints MIR for inspection.
3. **Link.** The pinned `lld` links the object with the embedded runtime and native standard library. `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

## One binary

`ms` also includes the formatter, linter, language server (`ms lsp`), interactive code maps (`ms diagram ms.toml --format html`), and profiling commands (`ms profile`). The standard library matches your `ms` version. Source-only commands such as `check`, `fmt`, `lint` and `diagram` work without native linking tools.

## Build tools and local setup

Native builds use `lld` to link the executable. Optimized builds also use LLVM tools when available. `ms` uses explicitly configured local tools first, then complete cached tools; it downloads missing tools from pinned releases and verifies their SHA-256 hashes.

| Tool | Local setting | Cache |
| --- | --- | --- |
| Linker | `MS_LLD`: path to a compatible `lld` executable | `<cache>/ms/lld/` |
| LLVM optimization | `MS_LLVM_TOOLS`: directory containing `opt`, `llc` and `llvm-link` | `<cache>/ms/llvm/` |

To avoid these tool downloads, provision the local tools or populate the matching caches beforehand. `MS_BACKEND=cranelift` skips LLVM optimization; a working linker is still required. If the LLVM download fails, the build falls back to Cranelift. If the linker is missing and cannot be downloaded, linking fails with guidance to set `MS_LLD`.

See [cache locations](builds/incremental-compilation.md) and [platform linking details](../contributing/rust-toolchain.md#differences-users-can-see). Compiling `ms` itself has separate [source-build prerequisites](../contributing/rust-toolchain.md#build-and-run).

## Runtime cache

The embedded runtime archive is extracted once and reused by later links. `ms build` can also reuse an unchanged executable; `run`, `test` and `profile` rebuild. See [build caches](builds/incremental-compilation.md) for locations and overrides.

## Where to go next

- [Build levels](builds/build-levels.md)
- [Build caches](builds/incremental-compilation.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
