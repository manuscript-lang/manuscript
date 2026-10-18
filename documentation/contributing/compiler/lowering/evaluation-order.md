+++
title = "Evaluation order and call preparation"
weight = 95
+++

# Evaluation order and call preparation

Generated Go must evaluate arguments in the order the caller wrote them, even when named arguments differ from declaration order.

- Consume the checker's resolved argument names (positional, named, mixed), evaluate each into a temporary in written order, then arrange them for the call. Preserve short-circuiting.
- `TaskGroup.start` prepares its callback before submitting. Closure construction snapshots captures without running bodies. Earlier submissions may already run while later ones prepare; lexical group cleanup stops and joins them if preparation fails.
- List elements evaluate left to right; an existing list argument evaluates once.
- Destructuring evaluates its initializer once and extracts bindings in pattern order, keeping each type.
- A `with` initializer evaluates once and registers the object's resolved `close` before the next cancellation checkpoint. Later alias assignment does not change that receiver.

See [source call order](../../../core-language/functions/declarations-and-calls.md) and [using with](../../../core-language/cleanup/scopes.md).
