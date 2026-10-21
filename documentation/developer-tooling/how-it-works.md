+++
title = "How it works"
weight = 0
+++

# How it works

`ms` is one self-contained binary. It checks your program and compiles it to a native executable with Cranelift. No other language toolchain is needed.

```text
.ms source → parse → check → compile → native executable
```

1. **Parse and check.** Resolves imports, then checks types, control flow, cleanup, and effects. Errors stop here.
2. **Compile.** `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

## One binary

`ms` also includes the formatter, linter, language server (`ms lsp`), and profiling commands (`ms profile`). The standard library matches your `ms` version. Nothing is downloaded at build time.

## Isolated from your machine

Caches live in the OS user cache directory; set `MANUSCRIPT_CACHE_DIR` to move them.

## Where to go next

- [Build levels](builds/build-levels.md)
- [Build caches](builds/incremental-compilation.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
