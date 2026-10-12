+++
title = "Typed intermediate representation"
weight = 91
+++

# Typed intermediate representation

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

After checking source, the compiler stores the program in a typed intermediate representation, or typed IR. It keeps the facts code generation and tooling need, rather than trying to rediscover them later.

| Fact | Why it remains explicit |
| --- | --- |
| Types, comparison bounds, and resolved operations | Preserve nominal contract identity and substituted generic implementation selection; select representations and validate API contracts |
| Argument names and parameters | Resolve omitted single-parameter labels and preserve checked parameter mapping and written evaluation order |
| Lists and typed tasks | Retain homogeneous element types and each Task[T] result type |
| Destructuring | Retain shapes, field bindings, and extraction order |
| Closure environments | Record snapshot captures and receiver references |
| `with` registration and cleanup scopes | Resolve `close()` and unwind exited scopes |
| Effects and concurrency API boundaries | Derive host/service relationships and diagrams |
| Source locations | Connect generated behavior back to source |

There are no ownership-transfer instructions or affine states. Runtime operation IDs and fixed execution parents belong to the concurrency runtime; source IR records the API calls and contexts used to establish them.

See [pipeline](pipeline.md), [evaluation lowering](../lowering/evaluation-order.md), and [metadata](../../developer-tooling/debugging/metadata.md).
