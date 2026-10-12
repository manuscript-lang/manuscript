+++
title = "Typed intermediate representation"
weight = 91
+++

# Typed intermediate representation

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The intermediate representation carries the checked program into lowering and supplies facts used by tooling.

| Fact | Why it remains explicit |
| --- | --- |
| Types, comparison bounds, and resolved operations | Preserve nominal contract identity and substituted generic implementation selection; select representations and validate API contracts |
| Argument names and parameters | Preserve named-call checking and written evaluation order |
| Lists and fixed positional packs | Retain homogeneous element types or each position's exact type |
| Destructuring | Retain shapes, field bindings, and extraction order |
| Closure environments | Record snapshot captures and receiver references |
| `with` registration and cleanup scopes | Resolve `close()` and unwind exited scopes |
| Effects and concurrency API boundaries | Derive host/service relationships and diagrams |
| Source locations | Connect generated behavior back to source |

There are no ownership-transfer instructions or affine states. Runtime operation IDs and fixed execution parents belong to the concurrency runtime; source IR records the API calls and contexts used to establish them.

See [pipeline](pipeline.md), [evaluation lowering](../lowering/evaluation-order.md), and [metadata](../../developer-tooling/debugging/metadata.md).
