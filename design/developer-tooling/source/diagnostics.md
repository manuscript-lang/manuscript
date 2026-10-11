+++
title = "Readable and structured diagnostics"
weight = 111
+++

# Readable and structured diagnostics

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Diagnostics serve both human readers and tools that need to locate a source problem.

Each diagnostic has a stable rule code, a readable message, and a primary source span. Related declarations or call sites use secondary spans. Source coordinates follow the [metadata span contract](../debugging/metadata.md).

## Explaining a violated rule

For example, a non-function entry in a parallel pack should identify the required callable type and source position. An invalid `with` initializer should identify the missing concrete implementation, contract operation, or generic-bound proof. A missing match alternative or unnamed argument should identify the relevant declaration and call-site location. Runtime closed-resource errors carry operation and source locations separately from static diagnostics.

The code catalog and serialized schema still need definitions. The rules being reported are defined by [type checking](../../compiler/frontend/type-checker.md) and [scope and capture checking](../../compiler/frontend/scope-checker.md).

[Previous: Structural edits and revision guards](../source/structural-editing.md) · [Next: System, flow, and detail views](../diagrams/views.md)
