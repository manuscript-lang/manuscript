+++
title = "Scope and capture checking"
weight = 90
+++

# Scope and closure checking

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The frontend validates cleanup registration and closure captures without a general ownership or lifetime checker.

| Source operation | Required check |
| --- | --- |
| `with` initializer | Require the concrete, contract-view, or generic-bound proof defined by [Closeable](../../ownership-and-cleanup/cleanup/closeable.md); register the resolved operation |
| Scope exit | Identify exited cleanup scopes for return, loop exits, errors, faults, and cancellation |
| Closure creation | Identify captured bindings and snapshot them once |
| Assignment to captured outer local | Reject implicit shared mutable cells |
| Reassignment and branch scope | Require initializers, enforce `let`/`var`, and keep branch-local names inside their scope |
| Concurrency eligibility | Retain type-level sharing through generic data/shared-contract boundaries; check callable value proofs separately at standard API entry |
| Callable proof erasure | Retain safe local capture proofs for direct standard callable arguments; erase them through generic forwarding, fields, and source function parameter/result boundaries; function types never satisfy Shareable |
| Call-only standard bindings | For resolved standard declaration identities only, reject extracting parallel, parallel_map, Background constructors, or Background.start as function/bound-method values; validate every direct call's required callable proofs. Same-spelled application functions follow ordinary function-value rules |

Capturing a scoped resource is not a compile error merely because it may outlive its scope. Methods report closed state at runtime. Storing or returning a reference does not transfer a cleanup action. There are no moved-binding states, borrow lifetimes, partial-move restrictions, or source task-ownership checks.

See [with scopes](../../ownership-and-cleanup/cleanup/scopes.md), [closures](../../core-language/functions/function-values-and-closures.md), and [typed IR](typed-ir.md).
