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

`ms check file.ms --json` emits `{"format": 1, "diagnostics": [...]}`. Each diagnostic has `code`, `phase`, `message`, and `position` with `file`, one-based `line`/UTF-8 byte `column`, and original-byte `offset`. Empty results use `[]`. CRLF normalization preserves original offsets. Codes identify rule families: MS1000 grammar, MS1001 literals/text, MS1002 layout; MS2001 names/members, MS2002 modules; MS3000 general typing, MS3001 exact types/operators, MS3002–3004 duplicate/missing/unknown arguments, MS3010–3012 implementations, MS3020 sharing, MS3021 hashing, MS3030 captures, MS3040 recursion, MS3050 exhaustiveness, MS3060 mutation, MS3070 numeric literals, MS3080 generic inference; MS4000 lowering. Full token-range and related-declaration spans remain a richer diagnostic revision. The rules being reported are defined by [type checking](../../compiler/frontend/type-checker.md) and [scope and capture checking](../../compiler/frontend/scope-checker.md).

[Previous: Structural edits and revision guards](../source/structural-editing.md) · [Next: System, flow, and detail views](../diagrams/views.md)
