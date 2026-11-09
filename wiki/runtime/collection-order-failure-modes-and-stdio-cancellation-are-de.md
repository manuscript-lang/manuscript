[Wiki](../index.md) › [Runtime](index.md)

# Collection order, failure modes, and stdio cancellation are decided

Decision: Map and Set iterate in insertion order, and keys use the `Hashable` interface with `Equal`. Pick a failure mode by cause: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. Mutators use verbs (`add`, `remove`, `clear`) and return the receiver (the value-semantics migration changes mutator results; see the ownership notes); do not reintroduce removed alias spellings (#358).

Apply when: adding or renaming collection, standard-library, or I/O members; choosing between Optional, Result, and a fault.
Evidence: [failure-mode rule](../../stdlib/intrinsics.ms), [collection order and mutation](../../documentation/core-language/types/collections.md), [equality interfaces](../../documentation/core-language/types/equality-and-hashing.md), [ownership notes](../../crates/ms-check/OWNERSHIP.md).
Verify: iteration after removals and re-adds keeps insertion order for the remaining keys; a new member documents its failure mode and has a doc comment with an example.

Combination traversal must not consume one call frame per chosen item (#3223).
Choosing an entire large list has one output, so its feasible output size does
not justify a call-depth fault. Advance a lexicographic position vector instead;
check zero-size results, equal-valued positions, nested independent copies and a
large full-size selection. Keep the documented invalid-size faults unchanged.
