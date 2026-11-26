[Wiki](../index.md) › [Compiler and build](index.md)

# Names are dense ids ordered by intern order, not text

Verified: a name is an `MsName`, a dense id into an `MsNames` table that owns the text (`src/base/intern.h`), so a name's text and alphabetical order need the table. Comparing ids is deterministic (intern order follows parse order) but not alphabetical. A table can sit over a frozen base table (`ms_names_init_over`), whose ids come first.

Rule: output a user or a snapshot sees (member lists, completions, `ms map --view inspect`, docs) must sort on the name's text, never on id order. A span from `ms_names_span` lives until `ms_names_free`; free a table only when no id or span from it is used afterward.

Apply when: sorting or comparing `MsName` values, or adding a long-lived process (the language server) that should free its names.
Evidence: `src/base/intern.h`, [proposal](../../proposals/session-owned-interner.md).
Verify: `ctest --preset ci`; an editor member list stays alphabetical.
