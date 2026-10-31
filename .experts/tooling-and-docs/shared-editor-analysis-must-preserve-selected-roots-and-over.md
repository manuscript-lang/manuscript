[Wiki](../index.md) › [Tooling and docs](index.md)

# Shared editor analysis must preserve selected roots and overlays

Verified: resolve the nearest manifest before sharing analysis. A standalone file symlink can select a different source root and confinement error from its destination; a symlinked manifest retains its containing directory. Distinct URIs can decode to one filename with different requested text, so those overlays cannot share a checked result. Keep default and selected-module recovery separate, private completion repair uncached, and strict workspace graphs transient. Apply queued incremental ranges in order and publish the newest errors before request, close, and EOF barriers. Successful cached graphs can survive edits outside their transitive module set; failed graphs may have missing dependencies and must refresh conservatively. Conflicting canonical overlay aliases affect even unrelated graphs.

Apply when: changing language-server analysis caching, workspaces, or scheduling.
Evidence: [analysis](../../crates/ms-lsp/src/analysis.rs), [workspace](../../crates/ms-lsp/src/workspace.rs), [overlays](../../crates/ms-driver/src/project/overlay.rs), [snapshot tests](../../crates/ms-lsp/tests/snapshots.rs).
Verify: compare cached results with uncached analysis in both query orders; [invalidation regressions](../../crates/ms-lsp/tests/analysis_invalidation.rs) cover transitive imports, missing files, changing import edges, close/watch barriers, and divergent URI aliases.

---
Topics: [Diagnostics and tooling](../topics/diagnostics-and-tooling.md)
