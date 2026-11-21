[Wiki](../index.md) › [Compiler and build](index.md)

# The C loader attaches packages, but the checker does not enforce them yet

Verified (`compiler/src/project/attach.c`, `compiler/tests/attach_test.c`, 2026-11): `ms_project_load_packages` loads a project with `[dependencies]` from `ms.lock` and the package cache, with the Rust texts for a missing lock entry, a tampered file and an effect a project has not allowed.

- A package module is named `@<repo>@<tag>/<path from the package root>`, imports in it resolve through the package's own `[aliases]` and dependencies, and a file is hashed against the locked index as it is read.
- `ms_project_load` still reports such a project as unsupported. The C checker has no package scope: it must reject native declarations in a fetched package and cap its effects (`cap` in `effect_reach.c` is never set), and the effect scan covers only the entry module. Until those exist, only a caller that enforces them may use `ms_project_load_packages`.
- Path dependencies and projects below a `[workspace]` root fall back to the Rust driver (the shared lock lives at the workspace root).
- `make target/c-tool/libmstool.a` needs `target/cmake/tools` removed after a CMake change; a stale cache gave `-lms_mimalloc` link errors.
