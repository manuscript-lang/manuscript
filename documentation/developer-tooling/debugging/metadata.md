+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

Metadata connects an executable and its runtime events to the exact source that produced them. Debugging and trace tools must check that connection before showing events on source code.

Keep static build facts separate from runtime observations:

| Record | Required information |
| --- | --- |
| Build manifest | Build identity, source hashes, source spans and statement boundaries, generated symbol/local mappings, type and variant descriptions, and static API sites |
| Run records | Run identity, operation IDs, fixed execution parents, join relationships, effective deadlines, events, timing, and outcomes; references to the matching build's static sites |

Source spans are half-open UTF-8 byte ranges in the original file. Newline normalization during parsing must retain a mapping to those original positions. Static IDs are deterministic within a build; operation IDs are interpreted within one run.

Before enabling debugging or trace overlays, match the manifest to the executable and source hashes. Reject mixed-build or mixed-run observations. Runtime operation IDs and deadlines cannot be emitted as completed facts at build time.

Storage schemas, event ordering/timestamps, and whether source bytes are embedded or loaded by hash still need concrete definitions.

See [build identity](../builds/reproducibility.md) and [source value interpretation](debugger-integration.md).

## Implemented static inspection

`ms inspect <module-or-project>` emits format-1 JSON with a source-derived build identity, original source hashes, deterministic entity IDs, generated declaration and local names, type descriptions, call sites including implicit cleanup, conservative transitive effects, and statement header spans. Header spans are half-open ranges in original bytes and exclude line terminators. `ms diagram` emits the checked static call graph as Mermaid. Native checked builds emit a separate executable/toolchain manifest.

Callable entities with bodies also carry an optional `entry` span for their own
first statement. Default-argument callback statements remain in the general
statement list, but do not become that callable's entry. Scripted function
breakpoints use `entry`; an absent entry cannot resolve a function-name breakpoint.

Generated source uses Go line directives, and source programming faults collect Manuscript function positions. `--debug` retains native symbols, disables optimization/inlining, and uses absolute source paths. Generated local identifiers retain source names. The VS Code Manuscript DAP adapter connects to Delve and renders checked local names, records, collections, variants, interface views, and execution/service inspection. Versioned rename and code actions validate source edits. Run-event transport and generalized structural transformations remain additional tooling contracts.
