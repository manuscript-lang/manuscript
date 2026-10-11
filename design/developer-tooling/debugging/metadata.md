+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Debugging and trace inspection need enough metadata to connect generated execution to the source program that produced it.

Keep static build facts separate from runtime observations:

| Record | Required information |
| --- | --- |
| Build manifest | Build identity, source hashes, source spans and statement boundaries, generated symbol/local mappings, type and variant descriptions, and static API sites |
| Run records | Run identity, operation IDs, fixed execution parents, join relationships, effective deadlines, events, timing, and outcomes; references to the matching build's static sites |

Source spans are half-open UTF-8 byte ranges in the original file. Newline normalization during parsing must retain a mapping to those original positions. Static IDs are deterministic within a build; operation IDs are interpreted within one run.

Before enabling debugging or trace overlays, match the manifest to the executable and source hashes. Reject mixed-build or mixed-run observations. Runtime operation IDs and deadlines cannot be emitted as completed facts at build time.

Storage schemas, event ordering/timestamps, and whether source bytes are embedded or loaded by hash still need concrete definitions.

See [build identity](../../compiler/builds/reproducibility.md) and [source value interpretation](debugger-integration.md).

[Previous: Execution traces and overlays](../diagrams/traces.md) · [Next: Generated Go source mapping](../debugging/source-mapping.md)
