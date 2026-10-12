+++
title = "References and sharing"
weight = 48
+++

# References and sharing

[Guide index](../_index.md) · [Design index](../../_index.md)

Several names can refer to the same object. These pages explain what happens when you pass, store, replace, or share those references. Keep two questions separate: is concurrent access safe, and is the resource still open?

- [Ordinary references](references.md) — Understand what another reference does, and why it does not keep a resource open.
- [Concurrent access and resource lifetime](sharing.md) — Check whether data or a function can safely be used by concurrent operations.
- [Aggregates and local construction](aggregates.md) — Store resources inside records or collections without assuming automatic cleanup.
- [Assignment and branches](control-flow.md) — See what reassignment and branches do to references and registered cleanup.
