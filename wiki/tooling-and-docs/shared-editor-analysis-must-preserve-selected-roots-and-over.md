[Wiki](../index.md) › [Tooling and docs](index.md)

# Shared editor analysis must preserve selected roots and overlays

Verified: resolve the nearest manifest before sharing analysis. A standalone file symlink can select a different source root and confinement error from its destination; a symlinked manifest retains its containing directory. Distinct URIs can decode to one filename with different requested text, so those overlays cannot share a checked result. Keep default and selected-module recovery separate, private completion repair uncached, and strict workspace graphs transient.

For source comparisons, a new unsaved file has the identity of its existing canonical parent plus its filename. Use the loader's `source_path` rules for this case: full-path canonicalization alone fails through directory links until the file is saved, losing hover and its open URI/version during rename. This comparison must not replace nearest-manifest selection or bypass root confinement, dangling-link rejection or conflicting-overlay checks.

Native filename separators must survive URI generation. On Unix a backslash is a filename byte, so only Windows may normalize it to `/`; otherwise `a\b.ms` aliases `a/b.ms` before workspace analysis even selects a root. The [URI separator regression](../../crates/ms-lsp/src/uri.rs) checks native behavior and keeps Windows verbatim-path controls.

Generated import paths need Manuscript string escaping, including literal braces; generic JSON/TOML/Go quoting does not preserve source meaning. Omit paths the import grammar cannot express, rather than replacing a Unix filename backslash with a separator. [Import hint regressions](../../crates/ms-driver/tests/import_hints.rs) check generated paths by parsing them back.

Import edits must use lexical statement boundaries, not delimiter characters in line text. A `)` inside a comment is not the end of a grouped import; inserting a first import must also leave a blank-terminated effect header at the top of its file. [Editing regressions](../../crates/ms-lsp/tests/editing_regressions.rs) apply the edits, recheck the source and preserve its effect permissions in LF and CRLF.

Apply when: changing language-server analysis caching, URI encoding, workspaces, or scheduling.
Evidence: [analysis](../../crates/ms-lsp/src/analysis.rs), [workspace](../../crates/ms-lsp/src/workspace.rs), [overlays](../../crates/ms-driver/src/project/overlay.rs), [snapshot tests](../../crates/ms-lsp/tests/snapshots.rs).
Verify: compare cached results with uncached analysis in both query orders; [invalidation regressions](../../crates/ms-lsp/tests/analysis_invalidation.rs) cover transitive imports, missing files, changing import edges, close/watch barriers, and divergent URI aliases.
The directory-link controls in [navigation identity](../../crates/ms-lsp/tests/navigation_identity.rs) cover new/saved files, canonical/alias buffers, hover, references and versioned rename from both sides of an import.
