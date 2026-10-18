+++
title = "How it works"
weight = 0
+++

# How it works

`ms` is one self-contained binary. It parses and checks your program, lowers it to Go, and compiles that Go with a toolchain it carries inside itself. You never install or configure Go.

## From `.ms` to an executable

```text
.ms source → parse → check → lower to Go → bundled Go compiler → native executable
```

1. **Parse and check.** The compiler reads your modules and resolves imports. It then checks types, bounds, control flow, cleanup, and effects. Errors stop here, before any Go exists.
2. **Lower to Go.** The checked program becomes typed Go with no boxing and no `any` in generated signatures: `Int` is Go `int`, a `List[T]` is a generic runtime list, and a function is a Go function. Evaluation order, closure captures, concurrency, and block-level cleanup are preserved. Generated names and declaration order are deterministic.
3. **Compile and link.** The embedded Go toolchain builds the generated code together with the Manuscript runtime into a native executable. `ms build` writes it; `ms run` and `ms test` build into a temporary directory and clean up.

`ms emit` stops after step 2 and writes the Go source. The [lowering pages](../contributing/compiler/lowering/_index.md) describe the translation in detail.

## One binary

Everything below ships inside `ms`:

| Part | What it does |
| --- | --- |
| Compiler and checker | Parse, check, format, lint, inspect, and lower source. These commands need no Go at all. |
| Go toolchain | A trimmed Go SDK holding only the tools and references the runtime needs, including cross-build references for the supported targets. It is extracted once into a cache keyed by its content hash. |
| Runtime and dependencies | The Manuscript runtime and its vendored, pinned dependencies, compiled offline. Nothing is downloaded during a build. |
| Standard library | The `@std` modules, pinned to the version of `ms` you run. |
| Language server | `ms lsp` powers editor diagnostics, navigation, completion, and rename. |
| Debugger | Delve is embedded, so `ms debug` and the VS Code extension work without a separate `dlv`. On macOS, Apple's `debugserver` from the Xcode command line tools is still required. |
| Profiling | `ms run --cpu-profile`, `ms profile`, `ms pprof`, and `ms trace` cover CPU, heap, and execution traces. |

## Isolated from your machine

Native commands ignore your Go installation and its environment. They use the bundled `GOROOT`, an offline module cache, no cgo, and private caches under the OS user cache directory (override it with `MANUSCRIPT_CACHE_DIR`). There is no fallback to a Go on your `PATH`. The same `ms` binary therefore produces the same generated code on any machine.

## Fast rebuilds

`ms` keeps no executable cache, so changed or invalid source can never run a stale binary. Speed comes from a shared workspace holding the compiled runtime, Go's package cache, and recorded compile and link commands that later builds replay. See [build caches](builds/incremental-compilation.md).

## Where to go next

- [Build levels](builds/build-levels.md) choose optimization and debugging settings.
- [Build pins and reproducibility](builds/reproducibility.md) lists what a build records.
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md) cover the debugger, language server, and profiling.
- [Architecture](../contributing/architecture.md) maps the compiler's packages for contributors.
