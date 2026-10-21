+++
title = "Build caches"
weight = 4
+++

# Build caches

Every `build`, `run`, `test`, and `profile` parses and checks source, lowers it to MIR, generates native object code with Cranelift, and links a fresh executable. Executables and compile/link plans are not cached.

The runtime and native standard library are already compiled into a static archive embedded in `ms`. The first link extracts `libms_native.a` into a cache keyed by the embedded runtime identity; later links reuse that archive. It is not rebuilt for each build level.

- The runtime cache is under `$XDG_CACHE_HOME/ms/native/`, falling back to `$HOME/.cache/ms/native/` or the OS temporary directory when neither variable is set.
- `build` writes the output you name and an adjacent `.ms-build.json` metadata file. `run`, `test`, and `profile` build in temporary directories; `profile` copies the executable into its capture directory.
- `run --watch` and `test --watch` keep the watcher alive and build fresh after changes.
- Old project `.ms-cache` directories are unused and can be deleted. `MANUSCRIPT_CACHE_DIR` does not override the native runtime cache or temporary build directories.

See [project configuration](project-configuration.md), [build levels](build-levels.md), and [how it works](../how-it-works.md).
