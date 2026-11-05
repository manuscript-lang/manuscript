+++
title = "Typed intermediate representation"
weight = 91
+++

# Typed intermediate representation

Use `Program::hir()` when adding a lowering or tooling query. HIR is a view over the syntax tree and per-module checker facts, not a separately rebuilt tree. Resolve an operation once in checking, then read that identity rather than inferring it again from a name.

| Fact | Why it stays explicit |
| --- | --- |
| Types, bounds, resolved operations | Preserve contract identity and generic implementation choice; select representations |
| Argument names and parameters | Keep resolved labels, parameter mapping, and written evaluation order |
| Lists | Keep element types |
| Destructuring | Keep shapes, field bindings, extraction order |
| Closure environments | Record borrowed or owned captures and receiver places |
| Resource bindings and cleanup scopes | Resolve `close()` and unwind exited scopes |
| Effects and host boundaries | Derive host/service relationships and diagrams |
| Source locations | Map generated behavior to source |

`Hir::ownership()` exposes move, borrow, mutation, and drop facts for lowering. Ownership checking rejects use after move and overlapping borrows before code generation; see the [ownership contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).

See [pipeline](pipeline.md), [evaluation lowering](../lowering/evaluation-order.md), and [metadata](../../../developer-tooling/debugging/metadata.md).
