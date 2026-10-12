+++
title = "Builds and projects"
weight = 2
+++

# Builds and projects

These pages explain how the compiler locates source files, optimizes native executables, records the versions used by a build, and reuses cached work. Start with the project manifest if you are setting up an application.

- [Project configuration](project-configuration.md) — Set the source directory, entry file, and import paths in `ms.toml`.
- [Build levels](build-levels.md) — Choose Debug, Release, RelWithDebInfo, or MinSizeRel.
- [Build pins and reproducibility](reproducibility.md) — Record versions and inputs so builds use the intended distribution.
- [Build caches](incremental-compilation.md) — Understand what a build reuses and what it checks again.
