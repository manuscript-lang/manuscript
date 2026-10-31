[Wiki](../index.md) › [Language](index.md)

# `for` walks `Iterator[T]` by expansion, not a new loop kind

Decision: `Iterator[T]` (`var def next() -> T?`, `@std/core.ms`) makes a type iterable. The checker records the loop as `while True: if let x = it.next(): body else: break` in the statement's `expansion` fact (with a hidden `var` unless the iterable is a variable or field path, which advances in place and keeps its final state), and lowering and the ownership passes read that expansion, so no loop-specific lowering exists. Formatter, lint and LSP still see the written `for`; the LSP does not index the loop variable of an iterator loop. The hidden `var` lives to the end of the enclosing block, not the loop. A read-only method named `next` without `impl Iterator` is deliberately not iterable (nominal conformance).

Apply when: adding iteration forms or changing what `for` accepts.
Verify: `tests/e2e/testdata/stdlib/io-lines.ms` (break/continue, interface-typed iterator, temporary) and `reject/iterator-let-loop.ms`.
