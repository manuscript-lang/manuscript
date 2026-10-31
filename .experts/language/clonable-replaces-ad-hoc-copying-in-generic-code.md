[Wiki](../index.md) › [Language](index.md)

# `Clonable` replaces ad hoc copying in generic code

Decision: `Clonable` is a prelude interface whose `value.clone()` returns an independent deep copy, so a generic body can keep a value it only borrows. Plain data and functions qualify; interface views, regular expressions and resource handles do not. Deque, Queue and sorted collections are vetted against it.

Apply when: writing generic stdlib code that stores or returns borrowed elements.
Evidence: [generics](../../documentation/core-language/types/generics.md), [declarations](../../documentation/core-language/modules/declarations.md).
Verify: a `[T: Clonable]` function can return `xs[0].clone()`; a resource handle fails the bound.

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md) · [Ownership and value semantics](../topics/ownership-and-values.md)
