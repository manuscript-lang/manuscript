+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

`ms inspect <module-or-project>` emits format-1 JSON with a source-derived build identity, original source hashes, deterministic entity IDs, generated declaration and local names, type descriptions, call sites including implicit cleanup, conservative transitive effects, and statement header spans. Header spans are half-open ranges in original bytes and exclude line terminators. `ms diagram` emits the checked static call graph as Mermaid. Native checked builds emit a separate executable/toolchain manifest.

Callable entities with bodies also carry an optional `entry` span for their own
first statement. Default-argument callback statements remain in the general
statement list, but do not become that callable's entry. Scripted function
breakpoints use `entry`; an absent entry cannot resolve a function-name breakpoint.

Generated source uses Go line directives, and source programming faults collect Manuscript function positions. `--debug` retains native symbols, disables optimization/inlining, and uses absolute source paths. Generated local identifiers retain source names. The VS Code Manuscript DAP adapter and scripted `ms debug` render checked local names, records, collections, and variants. Interactive `ms debug` and direct `ms dap` clients see Delve’s Go values. Versioned rename and code actions validate source edits.
