+++
title = "Scope and capture checking"
weight = 90
+++

# Scope and closure checking

The compiler checks which names a closure captures and which cleanup actions each scope must run. It does not prove that every resource reference stays within its open lifetime. Runtime closed-state checks still matter.

| Source operation | Required check |
| --- | --- |
| `with` initializer | Require the concrete, contract-view, or generic-bound proof defined by [Closeable](../../../core-language/cleanup/closeable.md); register the resolved operation |
| Scope exit | Identify exited cleanup scopes for return, loop exits, errors, faults, and cancellation |
| Closure creation | Identify captured bindings and snapshot them once |
| Assignment to captured outer local | Reject implicit shared mutable cells |
| Reassignment and branch scope | Require initializers, enforce `let`/`var`, and keep branch-local names inside their scope |

Capturing a scoped resource is not a compile error merely because it may outlive its scope. Methods report closed state at runtime. Storing or returning a reference does not transfer a cleanup action. There are no moved-binding states, borrow lifetimes, partial-move restrictions, or source task-ownership checks.

See [using with](../../../core-language/cleanup/scopes.md), [closures](../../../core-language/functions/function-values-and-closures.md), and [typed IR](typed-ir.md).

All values may be captured and shared. Specialized TaskGroup.start, Task.join, Scheduler.start, and HTTP serve methods are ordinary callable values. Constructors remain type constructors, not function values.
