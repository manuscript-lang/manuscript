[Wiki](../index.md) › [Runtime](index.md)

# Exclusive tree copies reject the destination before traversal

Verified: recursive `copy` applies its default EEXIST policy to an existing destination directory before reading or copying children. Testing only identical trees hid the missing directory check: a colliding leaf eventually failed, while empty or disjoint directories silently merged and earlier children could already have copied (#3292).

Keep explicit `replace: true` directory merging and root-filter exclusions intact. The native copier's internal skip-existing mode is separate from the public exclusive default.

Apply when: changing copy traversal, replacement policy, or directory admission.
Evidence: [native regression](../../crates/ms-std-fs/src/walk.rs), [called source regression](../../tests/e2e/testdata/stdlib/fs-defaults.ms).
Verify: empty and disjoint existing destinations return EEXIST without new children; explicit replacement retains unrelated destination files.
