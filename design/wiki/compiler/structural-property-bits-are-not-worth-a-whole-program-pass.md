[Wiki](../index.md) › [Compiler and build](index.md)

# Structural property bits are not worth a whole-program pass

Verified: audit item 25 proposed computing Equal, Hashable, Clonable and Data once per declared type. Two facts argue against it. A check of a typical program makes only about 270 structural property queries (`tasks.ms` and `sse.ms` conformance fixtures, about 80 ms for the whole debug check), so the per-query walk is not a cost. And the answer depends on `Method::visible_in(current_file)` over a method list that grows while modules register, so a single table per declared type would be wrong across files.

Rejected: a per-program `Vec<PropertyBits>`. Kept: `contracts::Property` replaces contract-name strings; the memo is per query. Revisit only with a measurement showing property queries dominate a large program's check time, and key any table by file visibility.

Apply when: changing `implements`, `satisfies`, or the structural property walk in `crates/ms-check/src/contracts.rs`.
Evidence: [property walk](../../crates/ms-check/src/contracts.rs).
Verify: `cargo test -p ms-check`.
