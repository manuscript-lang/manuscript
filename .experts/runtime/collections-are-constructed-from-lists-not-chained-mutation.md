[Wiki](../index.md) › [Runtime](index.md)

# Collections are constructed from lists, not chained mutation

Decision: `Set[Int]([3, 1, 2])` and `Set([3, 1, 2])` build a Set from a list (insertion order kept, duplicates collapsed); migrate chained `.add` construction in tests and examples. Do not add a second construction spelling (variadic, literal) without a new decision.

Apply when: adding collection constructors or writing fixtures that need a populated Set.
Evidence: [Set declaration](../../stdlib/collections.ms), [constructor uses](../../tests/e2e/testdata/stdlib/preferred-names.ms), commit c025937b.
Verify: duplicates collapse, first-seen order is kept, and `Set[Int]([])` is empty.
