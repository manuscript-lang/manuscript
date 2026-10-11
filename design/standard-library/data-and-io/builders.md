+++
title = "Local builders and immutable results"
weight = 43
+++

# Local builders and immutable results

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A builder supports mutable local construction and creates an immutable snapshot when frozen. Builder aliases are ordinary references; freezing may seal the builder so later mutation reports a runtime error.

Builders with unsynchronized mutable state are not eligible for concurrent sharing. There is no consuming function type or compiler-tracked ownership transfer. Frozen contents follow the ordinary collection element bounds.

The API still needs constructor and mutation signatures, the freeze result, repeated-freeze behavior, and the error for mutating a sealed builder. See [aggregates](../../ownership-and-cleanup/values/aggregates.md) and [collections](../../core-language/types/collections.md).
