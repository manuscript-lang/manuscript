+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

`ms inspect <module-or-project>` emits format-1 JSON with a source-derived build identity, original source hashes, deterministic entity IDs, generated declaration and local names, type descriptions, call sites including implicit cleanup, conservative transitive effects, and statement header spans. Header spans are half-open ranges in original bytes and exclude line terminators. `ms diagram` emits the checked static call graph as Mermaid. Native checked builds emit a separate executable/toolchain manifest.

Generated source uses Go line directives, so Delve maps native lines back to `.ms` statements. Source programming faults collect Manuscript function positions. `--debug` retains native symbols, disables optimization/inlining, and uses absolute source paths. Generated local identifiers retain source names. Only the VS Code adapter (`extensions/vscode/debug-adapter.js`) interprets values as Manuscript records, collections, and variants; `ms debug` and `ms dap` clients see Delve's Go values. Versioned rename and code actions validate source edits.
