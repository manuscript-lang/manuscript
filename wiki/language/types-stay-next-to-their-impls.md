[Wiki](../index.md) › [Language](index.md)

# Types stay next to their impls

Decision (Chinmay's preference): in `.ms` source, an `impl` block directly follows its type declaration (or another impl of the same type). Tracing a type's methods must not mean scanning the file. Methods stay in `impl` blocks; the grouping is the answer to scattered interface impls, not a language change.

Apply when: adding or moving types and impls in stdlib, examples, or docs.
Verify: `make repo-check` (`impl_adjacency.rs`) enforces it for `stdlib/`.
