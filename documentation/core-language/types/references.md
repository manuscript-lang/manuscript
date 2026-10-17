+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Several names can refer to the same object. Passing a reference to a function, putting it in a record, or capturing it in a closure gives another way to access that object. The original reference still works.

## Reassignment

Reassigning a `var` replaces its value or reference. It does not close the previous object or invalidate other references to it. A `let` prevents reassignment.

A `with` binding is immutable and registers the initialized object itself. Reassigning another variable that references the object cannot change which object's `close()` will execute. Closing early is permitted because `close()` is idempotent.

Every binding is initialized at declaration. Branch-local names stay inside their branch; assignments to an outer `var` keep its declared type. Closures snapshot the current value of a local binding at creation; they do not share mutable local cells.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [using with](../cleanup/scopes.md).

## Data copies

Record and collection aliases observe updates to the same instance. `.clone()` creates separate outer data storage and retains nested references. Cloning a record containing a file or socket retains that handle; it does not duplicate, reopen, or extend the resource's lifetime. Opaque handles do not have a built-in clone operation. See [mutation and cloning](records.md#mutation-and-cloning).

## References inside other values

Records, alternatives, collections, and closures can hold resource references. Storing a resource inside one of these values does not arrange for it to close or keep it open. Arrange cleanup for the resource itself.

Closing a registered resource affects all aliases, including aliases nested in aggregates. Dropping an aggregate does not recursively close its fields. A library object that deliberately manages several resources can implement `Closeable` and explicitly close them in its implementation.

Collections may retain any value, including resource references and functions. Sharing is universal and does not provide a resource lifetime guarantee.

Builders follow the same reference rules; they are not synchronized. [Destructuring](destructuring.md) extracts fields and positions without changing cleanup.

## Memory and open resources

The garbage collector reclaims memory that is no longer needed. Releasing a file handle, socket, or other external resource is a separate job. Use an explicit `close()` call or a `with` block to arrange that release.

Keeping a reference keeps the object accessible in memory. It does not keep an external resource open. When one reference closes a resource, operations through its other references also see that it is closed. Dropping a reference, closure, or work ID does not itself close anything.

## Returning a resource

A factory can return an open resource for its caller to put in `with`. But a function must not expect a resource to stay open merely because it returns it from inside a local `with` block. That block still closes the resource before the caller receives it.

| What the function does | What the caller receives |
| --- | --- |
| Returns an open resource without registering local cleanup | An open resource; the caller must arrange cleanup. |
| Returns a resource registered in a local `with` block | A reference to the resource after that block has closed it. |

Later use of a closed resource produces its runtime closed-state error.

The compiler does not catch every missing `with`. Libraries should provide scoped APIs and diagnostics to help callers avoid omissions. Manuscript has no move or ownership-transfer operation.

See [Closeable](../cleanup/closeable.md), [using with](../cleanup/scopes.md), and [closures](../functions/function-values-and-closures.md).
