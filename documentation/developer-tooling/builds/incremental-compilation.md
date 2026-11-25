+++
title = "Build caches"
weight = 4
+++

# Build caches

`ms build` always recompiles the whole program, and so do `run`, `test`, and `profile`. All of them reuse cached build tools and the embedded runtime archive, so you never need to clean caches by hand.

The runtime and native standard library are already compiled into a static archive embedded in `ms`. The first link extracts `libms_native.a` into a cache keyed by the embedded runtime's identity, and later links reuse it. The archive is the same for every build level.

- The runtime cache is under `$XDG_CACHE_HOME/ms/native/`, falling back to `$HOME/.cache/ms/native/` or the OS temporary directory when neither variable is set.
- Downloaded linking tools are cached under `<cache>/ms/lld/`. Complete caches are reused; explicitly configured local tools take precedence. These tool caches use `%LOCALAPPDATA%` on Windows, otherwise `$XDG_CACHE_HOME`, `$HOME/.cache`, or the OS temporary directory. `MS_LLD` selects a local linker and `MS_LLVM` a local LLVM library; see [build tools and local setup](../how-it-works.md#build-tools-and-local-setup).
- `build` writes the output you name and an adjacent `.ms-build.json` metadata file. `run`, `test`, and `profile` build in temporary directories; `profile` copies the executable into its capture directory.
- `run --watch` and `test --watch` keep the watcher alive and build fresh after changes.
- There is no build cache for compiled programs. You can delete a leftover `.ms-cache` directory from an older `ms`.
- `MANUSCRIPT_CACHE_DIR` does not override the native runtime cache or temporary build directories.

See [project configuration](project-configuration.md), [build levels](build-levels.md), and [build and share a program](../how-it-works.md).
