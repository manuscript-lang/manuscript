+++
title = "Scope and capture checking"
weight = 90
+++

# Scope and closure checking

The compiler checks which names closures capture and which cleanup each scope runs. It does not prove every resource reference stays within its open lifetime; runtime closed-state checks still matter.

| Source operation | Required check |
| --- | --- |
| `with` initializer | Require the proof defined by [Closeable](../../../core-language/cleanup/closeable.md); register the resolved operation |
| Scope exit | Identify exited cleanup scopes for return, loop exits, errors, faults, cancellation |
| Closure creation | Identify captured bindings and snapshot them once |
| Assignment to captured outer local | Reject implicit shared mutable cells |
| Reassignment and branch scope | Require initializers, enforce `let`/`var`, keep branch names in scope |

- Capturing a scoped resource is not an error even if it outlives the scope; methods report closed state at runtime.
- Storing or returning a reference transfers no cleanup action.
- There are no moved-binding states, borrow lifetimes, partial-move rules, or task-ownership checks.
- All values may be captured and shared. `TaskGroup.start`, `Task.join`, `Scheduler.start`, and HTTP `serve` methods are ordinary callable values; constructors are not.

See [using with](../../../core-language/cleanup/scopes.md), [closures](../../../core-language/functions/function-values-and-closures.md), and [typed IR](typed-ir.md).
