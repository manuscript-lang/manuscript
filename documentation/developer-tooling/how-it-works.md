+++
title = "How it works"
weight = 0
+++

# How it works

`ms` is one self-contained binary. It checks your program and compiles it to a native executable with a bundled toolchain. You never install Go.

```text
.ms source → parse → check → compile → native executable
```

1. **Parse and check.** Resolves imports, then checks types, control flow, cleanup, and effects. Errors stop here.
2. **Compile.** `ms build` writes the executable; `ms run` and `ms test` use a temporary directory.

## One binary

`ms` also includes the formatter, linter, language server (`ms lsp`), debugger (`ms debug`), and profiling commands. The standard library matches your `ms` version. Nothing is downloaded at build time.

macOS debugging still needs Apple's `debugserver` (Xcode command line tools).

## Isolated from your machine

Native commands ignore any Go installation on your machine. Caches live in the OS user cache directory; set `MANUSCRIPT_CACHE_DIR` to move them.

## Where to go next

- [Build levels](builds/build-levels.md)
- [Build caches](builds/incremental-compilation.md)
- [Debugging](debugging/_index.md) and [commands and editor setup](implementation.md)
