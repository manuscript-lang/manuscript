+++
title = "Builds and dependencies"
weight = 97
+++

# Builds and dependencies

[Guide index](../_index.md) · [Design index](../../_index.md)

These pages explain how the compiler locates source files, optimizes native executables, records the versions used by a build, and reuses cached work. Start with the project manifest if you are setting up an application.

- [Project configuration and module paths](project-configuration.md) — Set the source directory, entry file, and import paths in `ms.toml`.
- [Build levels and binary optimization](build-levels.md) — Choose Debug, Release, RelWithDebInfo, or MinSizeRel.
- [Pinned dependencies and deterministic output](reproducibility.md) — Record versions and inputs so builds use the intended distribution.
- [Caching and Go package boundaries](incremental-compilation.md) — Understand what can be cached and when Go must rebuild a package.
