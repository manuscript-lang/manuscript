+++
title = "Build caches"
weight = 4
+++

# Build caches

Every `build`, `run`, `test`, and `profile` parses and checks source, lowers it to MIR, generates native object code with Cranelift or LLVM (for optimized builds when available), and links a fresh executable. `ms build` alone reuses an unchanged executable (below); `run`, `test`, and `profile` always rebuild.

The runtime and native standard library are already compiled into a static archive embedded in `ms`. The first link extracts `libms_native.a` into a cache keyed by the embedded runtime identity; later links reuse that archive. It is not rebuilt for each build level.

- The runtime cache is under `$XDG_CACHE_HOME/ms/native/`, falling back to `$HOME/.cache/ms/native/` or the OS temporary directory when neither variable is set.
- The first native link downloads the pinned `lld` into `<cache>/ms/lld/`; optimized builds fetch LLVM tools into `<cache>/ms/llvm/`. These tool caches use `%LOCALAPPDATA%` on Windows, otherwise `$XDG_CACHE_HOME`, `$HOME/.cache`, or the OS temporary directory. `MS_LLD` and `MS_LLVM_TOOLS` select local tools; see [how it works](../how-it-works.md).
- `build` writes the output you name and an adjacent `.ms-build.json` metadata file. `run`, `test`, and `profile` build in temporary directories; `profile` copies the executable into its capture directory.
- `run --watch` and `test --watch` keep the watcher alive and build fresh after changes.
- `ms build` stores finished executables in `.ms-cache/build` beside the input file (the eight newest stay). The key includes the currently resolved entry file and enclosing `ms.toml` selection. An entry is valid while the size and modification time of every source file and that manifest match, so a hit skips loading, checking, and linking. Retargeting the entry symlink or creating a new or nearer manifest invalidates the selection. A new file that would shadow an existing import is not noticed until a listed file changes. `MS_CACHE=off` disables the cache and `MS_CACHE=verify` rebuilds and fails if the result differs from the cached executable. `.ms-cache` can be deleted at any time.
- `MANUSCRIPT_CACHE_DIR` does not override the native runtime cache or temporary build directories.

See [project configuration](project-configuration.md), [build levels](build-levels.md), and [how it works](../how-it-works.md).
