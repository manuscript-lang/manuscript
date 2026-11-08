[Wiki](../index.md) › [Tooling and docs](index.md)

# Workspace scans filter files before running the checker

Verified: `ms search_symbol` from the repository root (about 5,000 `.ms` fixtures) took 80 to 100 seconds, even for a name that matched nothing. The lexical prefilter treated every `import` as a local one (it read the token before `import` instead of the path after it), kept any file that spelled a matching name as a use, and the per-match reference search ran the checker on every file in the folder. The prefilter now keeps a file only for a declared name or a local import, and reference search skips files that never spell the name.

Apply when: changing workspace symbol, reference or `search_symbol` discovery.
Evidence: [workspace scan](../../crates/ms-lsp/src/workspace.rs), test `a_file_is_kept_only_for_a_name_it_declares_or_a_local_import`.
Verify: time `ms search_symbol append` and a nonmatching name from the repository root; each should take seconds, not minutes.

An import does not keep its importer in the scan when it names a standard module or a relative file the scan itself visits: that file reports its own declarations. Only aliases, escaped strings and files outside the scan do. At the repository root (5,486 files, 412 with local imports) this took a no-match `ms search_symbol` from 15 s to 1.5 s with identical output for real queries (#3145).
