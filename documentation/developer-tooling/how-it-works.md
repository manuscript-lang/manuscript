+++
title = "How it works"
weight = 0
+++

# How it works

`ms` is one self-contained binary: it checks your program, lowers it to Go, and compiles that with a bundled toolchain. You never install Go.

## From `.ms` to an executable

```text
.ms source → parse → check → lower to Go → bundled Go compiler → native executable
```

1. **Parse and check.** Resolves imports, then checks types, bounds, control flow, cleanup, and effects. Errors stop here.
2. **Lower to Go.** Output is typed Go with no boxing and no `any` in signatures: `Int` is Go `int`, `List[T]` a generic runtime list, a function a Go function. Names and order are deterministic.
3. **Compile and link.** The embedded toolchain builds it with the runtime. `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

`ms emit` stops after step 2 and writes the Go source. See the [lowering pages](../contributing/compiler/lowering/_index.md).

## One binary

Inside `ms`:

| Part | What it does |
| --- | --- |
| Compiler and checker | Parse, check, format, lint, inspect, lower. Needs no Go. |
| Go toolchain | Trimmed Go SDK with cross-build references, extracted once into a cache keyed by content hash. |
| Runtime and dependencies | The runtime and vendored, pinned dependencies, compiled offline. No downloads. |
| Standard library | `@std` modules, pinned to your `ms` version. |
| Language server | `ms lsp`: diagnostics, navigation, completion, rename. |
| Debugger | Embedded Delve; no separate `dlv`. macOS still needs Apple's `debugserver` (Xcode command line tools). |
| Profiling | `ms run --cpu-profile`, `ms profile`, `ms pprof`, `ms trace`: CPU, heap, traces. |

## Isolated from your machine

Native commands ignore your Go installation: bundled `GOROOT`, offline module cache, no cgo, private caches under the OS user cache directory (override with `MANUSCRIPT_CACHE_DIR`). The same `ms` produces the same generated code anywhere.

## Fast rebuilds

No executable cache, so stale binaries never run. Speed comes from a shared workspace with the compiled runtime, Go's package cache, and replayed compile and link commands. See [build caches](builds/incremental-compilation.md).

## Where to go next

- [Build levels](builds/build-levels.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
- [Architecture](../contributing/architecture.md) (contributors)
