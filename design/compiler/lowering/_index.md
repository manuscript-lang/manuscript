+++
title = "Go lowering"
weight = 92
+++

# Go lowering

[Guide index](../_index.md) · [Design index](../../_index.md)

Lowering translates checked Manuscript into Go. The generated code must preserve evaluation order, closure captures, concurrency, and block-level cleanup. These pages describe how the compiler carries those guarantees across the translation.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
