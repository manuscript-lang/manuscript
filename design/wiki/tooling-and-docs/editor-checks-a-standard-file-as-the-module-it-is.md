[Wiki](../index.md) › [Tooling and docs](index.md)

# The editor checks a standard file as the module it is

Verified: a bundled file opened in the editor was checked as a project file. Files that declare prelude names (`core`, `collections`, `string`) failed with "reuses a prelude name", the analysis did not resolve, and hover, jump and references returned nothing in them (about 10k of 70k stdlib identifiers had no hover). Separately, only the first `fn Type.method` of a receiver form emitted an occurrence for the receiver, so jump and hover on the receiver of every later method were empty.

Decision: the language server gives the entry module the logical name `@std/<file>` (`MsLoadOptions.entry_name`). The checker marks a module named `@std/...` as bundled (`ms_check_is_std`) and gives it library privileges, and other bundled modules import this copy. Each method writes its own receiver, so each is its own occurrence; do not fold receivers.

Apply when: changing what a module may declare, or a check keyed on `user_modules`; use `ms_check_is_std` for "library privileges", `user_modules` only for "listed in the index".
Evidence: `tests/lsp/stdlib_bodies`; scan every identifier of every stdlib file with hover and definition and expect no wrong targets.
Verify: `ctest -R lsp`.
