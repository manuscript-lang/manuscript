+++
title = "Assignment and branches"
weight = 52
+++

# Assignment and branches

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Reassigning a `var` replaces its value or reference. It does not close the previous object or invalidate other references to it. A `let` prevents reassignment.

A `with` binding is immutable and registers the initialized object itself. Reassigning another variable that references the object cannot change which object's `close()` will execute. Closing early is permitted because `close()` is idempotent.

Every binding is initialized at declaration. Branch-local names stay inside their branch; assignments to an outer `var` keep its declared type. Closures snapshot the current value of a local binding at creation; they do not share mutable local cells.

See [bindings](../../core-language/basics/bindings.md), [closure captures](../../core-language/functions/function-values-and-closures.md), and [with scopes](../cleanup/scopes.md).
