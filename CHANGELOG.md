# Changelog

Versions are dates: `2026.11.0` is the first release of November 2026. From that version, block syntax, ownership, `promise` and `wait`, `import` and `export`, the keys of `ms.toml`, `--json` shapes, and diagnostic code numbers are frozen. Diagnostic wording can change; the code keeps its meaning. The list is [what is frozen](documentation/core-language/stability.md).

## 2026.11.0

First public release.

- Install from the [getting started](documentation/learn/getting-started.md) page, or build the development compiler with `make build` (CMake, Ninja, and clang). The binary is `.artifacts/build/ci/src/cli/ms`.
- `ms init`, `ms run`, `ms check`, `ms fmt`, `ms test`, `ms build`, and `ms map` are the commands a new project uses.
- One `ms` binary holds the compiler, standard library, and runtime. `ms build` writes a native executable.
