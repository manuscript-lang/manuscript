+++
title = "Developer tooling"
weight = 107
+++

# Developer tooling guide

[Design index](../_index.md)

Use the tools to format source, read diagnostics, and inspect program structure. Later sections describe diagrams, traces, and planned source-level debugging. Consult implementation coverage for features that are still design work.

## Reading order

### 1. [Source tools](source/_index.md)

- [Canonical formatting and generated views](source/formatting.md)
- [Structural edits and revision guards](source/structural-editing.md)
- [Readable and structured diagnostics](source/diagnostics.md)

### 2. [Diagrams and traces](diagrams/_index.md)

- [System, flow, and detail views](diagrams/views.md)
- [Reading a concurrent-flow diagram](diagrams/flow.md)
- [Architecture diffs](diagrams/architecture-diffs.md)
- [Execution traces and overlays](diagrams/traces.md)

### 3. [Debugging](debugging/_index.md)

- [Build, source, and task metadata](debugging/metadata.md)
- [Generated Go source mapping](debugging/source-mapping.md)
- [Debugger transport and source interpretation](debugging/debugger-integration.md)
