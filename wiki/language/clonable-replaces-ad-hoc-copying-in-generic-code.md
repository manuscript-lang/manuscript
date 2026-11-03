[Wiki](../index.md) › [Language](index.md)

# `Clonable` replaces ad hoc copying in generic code

Decision: `Clonable` is a prelude interface whose `value.clone()` returns an independent deep copy, so a generic body can keep a value it only borrows. Plain data and functions qualify; interface views, resource handles and natives without a `clone` of their own (regular expressions, pipes) do not. A native becomes `Clonable` by declaring `fn clone() Self` (`List`, `Bytes`, `BigInt`) or `impl Copy`; the checker derives the rule from those declarations, not from a name list. Deque, Queue and sorted collections are vetted against it.


Apply when: writing generic stdlib code that stores or returns borrowed elements.
Evidence: [generics](../../documentation/core-language/types/generics.md), [declarations](../../documentation/core-language/modules/declarations.md).
Verify: a `[T: Clonable]` function can return `xs[0].clone()`; a resource handle or a `Regex` fails the bound, and `re.clone()` is unresolved.
