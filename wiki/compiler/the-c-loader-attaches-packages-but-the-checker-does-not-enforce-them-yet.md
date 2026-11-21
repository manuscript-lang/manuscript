[Wiki](../index.md) › [Compiler and build](index.md)

# The C loader attaches packages; package rules need a complete effect scan

Verified (`compiler/src/project/attach.c`, `compiler/tests/attach_test.c`, 2026-11): `ms_project_load_packages` loads a project with `[dependencies]` from `ms.lock` and the package cache, with the Rust texts for a missing lock entry, a tampered file and an effect a project has not allowed.

- A package module is named `@<repo>@<tag>/<path from the package root>`, imports in it resolve through the package's own `[aliases]` and dependencies, and a file is hashed against the locked index as it is read.
- Package rules live in `ms_graph_check_packages` (`graph_check.c`, effect scan generalised to package modules in `effect_facts.c`): native declarations in a non-member package, and a package callable reaching an effect its `[project] effects` lacks (the `cap` of its nodes), with the Rust texts. It sets `*complete` false when the scan cannot see through a package callable (unchecked body, interface call it does not yet follow), and then the build must go to Rust: a missing error proves nothing. The project's own effect violations are lint findings in Rust, not build errors, so the C check does not report them.
- `ms_project_load` still reports package projects as unsupported; the CLI's check pipeline calls `ms_project_load_packages`, `ms_graph_check` and `ms_graph_check_packages`, and falls back when `*complete` is false.
- Path dependencies and workspace members load too (`workspace.c`: members, the lock at the workspace root, module names `@workspace/<name>/...`, members may declare natives). `tools/ms/workspace.ms` wraps `ms_tool_workspace`, so there is one workspace reader, in C, because the compiler needs it during a build.
- The C manifest reader never answers "unsupported" for syntax. Invalid TOML is `invalid ms.toml: <reason>` at the failing token, with reasons worded as in `stdlib/data/toml.ms` (expected key, expected equals, unterminated string, ...); valid TOML that ms.toml does not use (dotted keys, `[a.b]`, `[[a]]`, multi-line strings) is named as such. The detail text differs from the `toml_edit` wording of the Rust driver; the position and the `invalid ms.toml:` prefix are kept.
- `make target/c-tool/libmstool.a` needs `target/cmake/tools` removed after a CMake change; a stale cache gave `-lms_mimalloc` link errors.
