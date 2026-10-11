+++
title = "Ordinary references"
weight = 49
+++

# Ordinary references

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Values are ordinary data or references to runtime objects. Passing, returning, storing, and capturing a reference keeps the same object accessible. It does not invalidate the previous binding, schedule cleanup, or extend a resource's open lifetime.

Memory is reclaimed by Go garbage collection. External resources are released by explicit calls or `with`. Dropping an object reference, closure, or work ID is not an external cleanup operation.

A resource factory can return an open object for a caller to place in `with`. Returning an object already registered in a local `with` scope does not cancel that scope's cleanup; callers receive a closed object after the function exits. Closed-resource access is a runtime error.

The design does not prevent every missed `with` registration at compile time. Libraries should expose scoped resource APIs and diagnostics for common omissions. There is no move or ownership-transfer mechanism.

See [Closeable](../cleanup/closeable.md) and [closures](../../core-language/functions/function-values-and-closures.md).
