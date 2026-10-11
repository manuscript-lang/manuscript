+++
title = "Evaluation order and call preparation"
weight = 95
+++

# Evaluation order and call preparation

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Resolve each source argument name to its parameter, evaluate arguments into temporaries in written order, then arrange Go parameters. Preserve short-circuit control flow.

A `tasks: [...]` literal constructs a typed pack of function values in source order. Constructing closures snapshots their local captures; it does not invoke their bodies. If preparation fails, the concurrency API has not started work. Native acquisitions during preparation retain their explicit delivery/cleanup contracts.

Ordinary list elements evaluate left to right; an existing list argument evaluates once. Destructuring evaluates the initializer once and extracts bindings in written pattern order, retaining each positional result type.

A `with` initializer evaluates once, then registers the initialized object's resolved close method before exposing another cancellation checkpoint. Later alias assignment does not change that receiver.

See [source call order](../../core-language/functions/declarations-and-calls.md), [operation preparation](../../concurrency/parallel.md#preparation), and [with scopes](../../ownership-and-cleanup/cleanup/scopes.md).
