+++
title = "Scope and capture checking"
weight = 90
+++

# Scope and closure checking

The compiler checks which names closures capture and which cleanup each scope runs. It does not prove every resource reference stays within its open lifetime; runtime closed-state checks still matter.

| Source operation | Required check |
| --- | --- |
| Binding that holds a resource | Require the proof defined by [Closeable](../../../core-language/cleanup/closeable.md); register the resolved operation |
| Scope exit | Identify exited cleanup scopes for return, loop exits, errors, faults, cancellation |
| Closure creation | Identify captured bindings and infer borrowed non-escaping or owned escaping captures |
| Assignment to captured outer local | Allow mutation only through an exclusive non-escaping capture; escaping captures cannot be mutated |
| Reassignment and branch scope | Require initializers, enforce `let`/`var`, keep branch names in scope |

- Capturing a scoped resource is not an error even if it outlives the scope; methods report closed state at runtime.
- Storing or returning a reference transfers no cleanup action.
- Ownership checking tracks moved bindings, last uses, lexical borrows, exclusive mutation, and drops. No lifetime annotations appear in source.
- Escaping closures own their captures and cannot move them out on each invocation; non-escaping closures borrow. HTTP `serve` methods are ordinary callable values; constructors are not.

See [using with](../../../core-language/cleanup/scopes.md), [closures](../../../core-language/functions/function-values-and-closures.md), and [typed IR](typed-ir.md).
