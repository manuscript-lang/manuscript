+++
title = "Build caches"
weight = 4
+++

# Build caches

`ms build` can reuse an unchanged executable. `run`, `test`, and `profile` always check and compile the program again. Both paths reuse cached build tools and the embedded runtime archive, so you can keep working without manually cleaning caches.

## Understand what is being reused

There are three different things to reuse: tools that link or optimize any program, the runtime archive shared by programs built with this compiler, and a finished executable for one particular set of inputs. Keeping a linker in the cache does not mean the source check was skipped. Conversely, a finished-executable cache hit can skip the frontend entirely.

During ordinary editing, use `run` or a [watch session](../implementation.md#rebuild-on-save) for fresh execution. If a `build` result seems stale after changing the project layout or preserving file timestamps, rebuild with `MS_CACHE=off` to separate reuse from compilation. This environment setting applies to the finished-executable cache; it does not remove downloaded tools. Use your shell's environment-variable syntax when setting it.

## Cache locations and contracts

The runtime and native standard library are already compiled into a static archive embedded in `ms`. The first link extracts `libms_native.a` into a cache keyed by the embedded runtime identity; later links reuse that archive. It is not rebuilt for each build level.

- The runtime cache is under `$XDG_CACHE_HOME/ms/native/`, falling back to `$HOME/.cache/ms/native/` or the OS temporary directory when neither variable is set.
- Downloaded linking tools are cached under `<cache>/ms/lld/` and optimization tools under `<cache>/ms/llvm/`. Complete caches are reused; explicitly configured local tools take precedence. These tool caches use `%LOCALAPPDATA%` on Windows, otherwise `$XDG_CACHE_HOME`, `$HOME/.cache`, or the OS temporary directory. `MS_LLD` and `MS_LLVM_TOOLS` select local tools; see [build tools and local setup](../how-it-works.md#build-tools-and-local-setup).
- `build` writes the output you name and an adjacent `.ms-build.json` metadata file. `run`, `test`, and `profile` build in temporary directories; `profile` copies the executable into its capture directory.
- `run --watch` and `test --watch` keep the watcher alive and build fresh after changes.
- `ms build` stores finished executables in `.ms-cache/build` beside the input file (the eight newest stay). The key includes the currently resolved entry file and enclosing `ms.toml` selection. An entry is valid while the size and modification time of every source file and that manifest match, so a hit skips loading, checking, and linking. Retargeting the entry symlink or creating a new or nearer manifest invalidates the selection. A new file that would shadow an existing import is not noticed until a listed file changes. `MS_CACHE=off` disables the cache and `MS_CACHE=verify` rebuilds and fails if the result differs from the cached executable. `.ms-cache` can be deleted at any time.
- `MANUSCRIPT_CACHE_DIR` does not override the native runtime cache or temporary build directories.

See [project configuration](project-configuration.md), [build levels](build-levels.md), and [build and share a program](../how-it-works.md).
