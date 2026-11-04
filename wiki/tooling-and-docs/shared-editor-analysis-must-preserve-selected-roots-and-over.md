[Wiki](../index.md) › [Tooling and docs](index.md)

# Shared editor analysis must preserve selected roots and overlays

Verified: resolve the nearest manifest before sharing analysis. A standalone file symlink can select a different source root and confinement error from its destination; a symlinked manifest retains its containing directory. Distinct URIs can decode to one filename with different requested text, so those overlays cannot share a checked result. Keep default and selected-module recovery separate, private completion repair uncached, and strict workspace graphs transient.

For source comparisons, a new unsaved file has the identity of its existing canonical parent plus its filename. Use the loader's `source_path` rules for this case: full-path canonicalization alone fails through directory links until the file is saved, losing hover and its open URI/version during rename. This comparison must not replace nearest-manifest selection or bypass root confinement, dangling-link rejection or conflicting-overlay checks.

Apply when: changing language-server analysis caching, workspaces, or scheduling.
Evidence: [analysis](../../crates/ms-lsp/src/analysis.rs), [workspace](../../crates/ms-lsp/src/workspace.rs), [overlays](../../crates/ms-driver/src/project/overlay.rs), [snapshot tests](../../crates/ms-lsp/tests/snapshots.rs).
Verify: compare cached results with uncached analysis in both query orders; [invalidation regressions](../../crates/ms-lsp/tests/analysis_invalidation.rs) cover transitive imports, missing files, changing import edges, close/watch barriers, and divergent URI aliases.
The directory-link controls in [navigation identity](../../crates/ms-lsp/tests/navigation_identity.rs) cover new/saved files, canonical/alias buffers, hover, references and versioned rename from both sides of an import.
