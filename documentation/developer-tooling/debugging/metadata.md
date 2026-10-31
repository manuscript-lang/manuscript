+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

- `ms inspect <module-or-project>` emits format-2 JSON: build identity, source hashes, deterministic entity IDs, generated declaration and local names, types, call sites including implicit cleanup, conservative transitive effects, and statement header spans (half-open original-byte ranges excluding line terminators).
- `ms diagram` emits the static call graph as ascii (default) or Mermaid (`--format mermaid`).

- Native builds keep frame pointers and DWARF line tables that map machine addresses back to `.ms` lines. They do not describe variables or types, and the Rust `ms` has no debugger; see [profiling and native debugging](debugger-integration.md).
- `--build-type Debug` disables optimization for a build.
