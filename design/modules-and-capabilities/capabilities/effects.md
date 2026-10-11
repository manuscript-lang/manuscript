+++
title = "Inferred effects and call relationships"
weight = 81
+++

# Inferred effects and call relationships

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Effects describe behavior reachable through an operation, including behavior performed by its callees.

Effects are inferred transitively. Foreign adapters supply declared effect summaries. The effect vocabulary is read, write, external-call, and unknown. An unresolved function-value or contract call contributes unknown, never an empty effect set. Known targets contribute their union. A contract reports reachable behavior; Manuscript has no source effect-bound syntax or static purity promise. Foreign code is trusted to honor its summaries. External writes are not reversible through cancellation.

## Transitive analysis

A function calling an operation that writes externally inherits that external effect in the derived summary. Foreign adapters must declare summaries because source analysis cannot inspect their behavior as ordinary Manuscript calls.

Cancellation can stop unfinished work and trigger cleanup, but it cannot undo an external write that has already completed. A review of a boundary must therefore consider effects as well as returned errors.

See [diagram views](../../developer-tooling/diagrams/views.md) and [architecture changes](../../developer-tooling/diagrams/architecture-diffs.md).

[Previous: Explicit capability authority](../capabilities/authority.md) · [Next: Adapter manifests](../adapters/manifests.md)
