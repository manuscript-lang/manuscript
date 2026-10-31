[Wiki](../index.md) › [Language](index.md)

# `ref` is removed; results and fields own their value

Decision: Chinmay asked for `ref` to be removed after the one-borrow model left it as the last lending marker. A result and a record field own their value; a function that returns part of a parameter returns `.clone()`, and copy elision (a dead or read-only source is not copied) keeps the common getter free. `ref` stays a reserved word so the parser can say what to write. Bindings still borrow places without a marker (`let` shared, `var` exclusive), loops and matches over a parameter borrow it unless a payload moves out, and there are no lifetimes to teach. Everything resource-like is `Clonable` (sockets and file descriptors duplicate their handle), so `.clone()` is available wherever a body keeps a part.

Apply when: changing result types, bindings, interface operation agreement, iteration protocols or the ownership pass. Do not reintroduce a lending marker, a borrowing record, or a result that views its argument; reach for copy elision or an index-based protocol first.
Evidence: [remove-ref proposal](../../proposals/remove-ref.md), [ownership notes](../../crates/ms-check/OWNERSHIP.md), [references](../../documentation/core-language/types/references.md).
Verify: `fn list() ref List[Int]` is a parse error naming `.clone()`; `fn list() List[Int]: return self.items` is rejected with the `.clone()` remedy; `for item in deque` reads by index without copying the deque.

---
Topics: [Ownership and value semantics](../topics/ownership-and-values.md)
