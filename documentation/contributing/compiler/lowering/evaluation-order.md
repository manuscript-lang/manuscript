+++
title = "Evaluation order and call preparation"
weight = 95
+++

# Evaluation order and call preparation

Lowered code must evaluate arguments in the order the caller wrote them, even when named arguments differ from declaration order.

- Consume the checker's resolved argument names (positional, named, mixed), evaluate each in written order, then place the values by parameter position. Preserve short-circuiting.
- Closure construction snapshots captures without running bodies.
- List elements evaluate left to right; an existing list argument evaluates once.
- Destructuring evaluates its initializer once and extracts bindings in pattern order, keeping each type.
- A `with` initializer evaluates once and registers the object's resolved `close` before the next checkpoint. Later alias assignment does not change that receiver.
- A value produced before a later operand that may return early (`try`) is held as a temporary so it is dropped on that exit.

See [source call order](../../../core-language/functions/declarations-and-calls.md) and [using with](../../../core-language/cleanup/scopes.md).
