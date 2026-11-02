[Wiki](../index.md) › [Language](index.md)

# An unsaved overlay cannot replace a dangling source symlink

Decision: editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target identity must be respected. Treating every not-found canonicalization result as an unsaved file would let an overlay hide an unresolved external target.


Apply when: changing project resolution, filesystem identity, or editor overlays.
Evidence: [overlay canonicalization](../../crates/ms-driver/src/project/overlay.rs), [symlink identity regression](../../crates/ms-driver/tests/project_project.rs).
Verify: new confined overlay files compile without being written to disk; overlays for outside paths, dangling external links, or symlinked external parents are rejected.
