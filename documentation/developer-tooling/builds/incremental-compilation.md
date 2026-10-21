+++
title = "Build caches"
weight = 4
+++

# Build caches

Executables are never cached, so an edited or invalid source never runs a stale binary. Every `build`, `run`, `test`, `debug`, and `profile` parses, checks, and builds fresh.

Rebuilds are fast because `ms` reuses the compiled runtime and replays the recorded compile and link steps when imports are unchanged. If anything is missing or fails, it falls back to a full build and refreshes the record.

- `build` writes the output you name; the other commands build into a temporary directory and remove it afterwards.
- Caches live in the OS user cache directory. `MANUSCRIPT_CACHE_DIR` overrides it, including the toolchain cache.
- Older versions wrote executables to a project `.ms-cache` or beside `-o` output. `ms` no longer reads or removes them, so delete any that remain.
- `run --watch` and `test --watch` keep one process between rebuilds, so only the application is rebuilt.

The first build at each build level is slower because it prepares the runtime for that level.

See [project configuration](project-configuration.md) and [how it works](../how-it-works.md).
