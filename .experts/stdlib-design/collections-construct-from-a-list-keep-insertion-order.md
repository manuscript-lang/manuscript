[Wiki](../index.md) › [Standard-library design](index.md)

# Collections: construct from a list, keep insertion order

Decision: `Set(list)` constructs from a list; Map and Set iterate in insertion order; mutators are verbs that return the receiver. See [runtime.md](../runtime/index.md) for the failure-mode and order rules.

Apply when: adding collection constructors, conversions (`to_set`), or fixtures.
Evidence: commit c025937b, [collections.ms](../../stdlib/collections.ms).
Verify: `Set([3, 1, 2])` iterates 3, 1, 2.
