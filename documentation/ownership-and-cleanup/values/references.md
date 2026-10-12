+++
title = "Ordinary references"
weight = 49
+++

# Ordinary references

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Several names can refer to the same object. Passing a reference to a function, putting it in a record, or capturing it in a closure gives another way to access that object. The original reference still works.

## Data copies

Record and collection aliases observe updates to the same instance. `.clone()` creates separate outer data storage and retains nested references. Cloning a record containing a file or socket retains that handle; it does not duplicate, reopen, or extend the resource's lifetime. Opaque handles do not have a built-in clone operation. See [mutation and cloning](../../core-language/types/records.md#mutation-and-cloning).

## Memory and open resources

Go's garbage collector reclaims memory that is no longer needed. Releasing a file handle, socket, or other external resource is a separate job. Use an explicit `close()` call or a `with` block to arrange that release.

Keeping a reference keeps the object accessible in memory. It does not keep an external resource open. When one reference closes a resource, operations through its other references also see that it is closed. Dropping a reference, closure, or work ID does not itself close anything.

## Returning a resource

A factory can return an open resource for its caller to put in `with`. But a function must not expect a resource to stay open merely because it returns it from inside a local `with` block. That block still closes the resource before the caller receives it.

| What the function does | What the caller receives |
| --- | --- |
| Returns an open resource without registering local cleanup | An open resource; the caller must arrange cleanup. |
| Returns a resource registered in a local `with` block | A reference to the resource after that block has closed it. |

Later use of a closed resource produces its runtime closed-state error.

The compiler does not catch every missing `with`. Libraries should provide scoped APIs and diagnostics to help callers avoid omissions. Manuscript has no move or ownership-transfer operation.

See [Closeable](../cleanup/closeable.md), [with scopes](../cleanup/scopes.md), and [closures](../../core-language/functions/function-values-and-closures.md).
