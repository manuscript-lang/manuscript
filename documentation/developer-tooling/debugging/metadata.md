+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

- `ms inspect <module-or-project>` emits format-2 JSON: build identity, source hashes, deterministic entity IDs, generated declaration and local names, types, call sites including implicit cleanup, conservative transitive effects, and statement header spans (half-open original-byte ranges excluding line terminators).
- `ms diagram ms.toml --format html -o code-map.html` creates an [interactive code map](../implementation.md#interactive-code-map) with source, checked types and connected views. ASCII and Mermaid formats provide focused static diagrams.

- Native builds keep frame pointers and DWARF line tables that map machine addresses back to `.ms` lines. Use these mappings for fault traces and native profiling; see [profiling and native debugging](debugger-integration.md).
- `--build-type Debug` disables optimization for a build.
