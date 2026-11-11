[Wiki](../index.md) › [Language](index.md)

# Types stay next to their impls

Decision (Chinmay's preference): in `.ms` source, a type's receiver methods directly follow its declaration. Tracing a type's methods must not mean scanning the file. (Written when methods lived in `impl` blocks; the keyword is gone and the rule carries over to `fn Type.name`.)

Apply when: adding or moving types and impls in stdlib, examples, or docs.
Verify: `make repo-check` (`impl_adjacency.rs`) enforces it for `stdlib/`.
