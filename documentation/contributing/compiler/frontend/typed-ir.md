+++
title = "Typed intermediate representation"
weight = 91
+++

# Typed intermediate representation

After checking, the program is stored as typed IR holding the facts code generation and tooling need, so they are never rediscovered.

| Fact | Why it stays explicit |
| --- | --- |
| Types, bounds, resolved operations | Preserve contract identity and generic implementation choice; select representations |
| Argument names and parameters | Keep resolved labels, parameter mapping, and written evaluation order |
| Lists | Keep element types |
| Destructuring | Keep shapes, field bindings, extraction order |
| Closure environments | Record snapshot captures and receiver references |
| `with` and cleanup scopes | Resolve `close()` and unwind exited scopes |
| Effects and host boundaries | Derive host/service relationships and diagrams |
| Source locations | Map generated behavior to source |

There are no ownership-transfer instructions or affine states.

See [pipeline](pipeline.md), [evaluation lowering](../lowering/evaluation-order.md), and [metadata](../../../developer-tooling/debugging/metadata.md).
