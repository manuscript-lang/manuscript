+++
title = "Execution traces and overlays"
weight = 116
+++

# Execution traces and overlays

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A flow diagram shows what a program can do. A trace records what happened during one run. A trace overlay places those observations on the matching diagram so you can follow timing and outcomes.

## Matching observations to source

Concurrent task scheduling and external effects can vary between executions. The overlay should report the observed timing and outcomes rather than imply that one observed order is guaranteed.

Trace overlays are enabled only when metadata matches the executable. Operation identities, fixed execution parents and API join relationships, and effective deadlines come from the build/runtime metadata contract.

See [metadata identity checks](../debugging/metadata.md) and [scheduling guarantees](../../concurrency/parallel.md#preparation).

[Previous: Architecture diffs](architecture-diffs.md) · [Next: Build, source, and task metadata](../debugging/metadata.md)
