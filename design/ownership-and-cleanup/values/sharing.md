+++
title = "Concurrent access and resource lifetime"
weight = 50
+++

# Concurrent access and resource lifetime

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

`Shareable` means safe concurrent access. It does not keep a resource open or register cleanup. A closure may retain a resource after its `with` scope exits; later operations then report the resource's closed-state error.

## Data and services

Immutable data derives sharing from its components. Trusted native services declare sharing only when their mutable state and resource lifecycle are synchronized. A resource may serialize simultaneous calls or reject overlapping use explicitly.

Wrappers coordinate the closed-state check, access to the underlying handle, and closure as one lifecycle protocol. A flag check followed by unprotected I/O is insufficient. A stale lease must never access a connection reused for another caller.

## Contract views

A plain contract view carries no sharing guarantee. `Contract & Shareable` retains a statically proved safe receiver through fields, parameters, returns, and collections. Explicit conversion to a plain view discards that proof; inspecting the hidden receiver cannot recover it. [Contract views](../../core-language/types/contracts.md#shared-contract-views) define construction and conversion.

A generic behavioral bound alone does not prove sharing; concurrent code needs `T: Shareable & Contract`. A shared receiver does not make its operation's parameters or results shareable.

## Function values

Function signatures describe calls, not captures. Source function types never satisfy the type-level `Shareable` bound. The compiler instead tracks a separate proof for each named function, closure, or bound method.

| Boundary | Callable sharing proof |
| --- | --- |
| Named source function | Safe: no captured local environment |
| Local closure | Safe when every capture has a type-level sharing guarantee or a retained callable proof |
| Bound method | Requires a shareable receiver; a plain view cannot reveal its hidden receiver's proof |
| Local copy or capture | Retains the known proof |
| `var` assignment or branch merge | Requires the proof for every possible value |
| Source function parameter or result, function field, or generic forwarding | Erases the proof; concurrent invocation is rejected |
| Direct standard callback argument | Checks the value's retained proof rather than a generic type bound |

A safe local closure therefore cannot instantiate `F: Shareable`. Passing it through `identity[T]` also loses its callable proof. These rules prevent storage or generic helpers from bypassing concurrent-call checks while preserving ordinary sequential function calls.

Capture application services and job data for background work, and acquire job resources inside that work's own `with` scopes. See [background services](../../standard-library/tasks/background.md), [generic bounds](../../core-language/types/generics.md), and [resource release](../cleanup/resource-release.md).
