[Wiki](../index.md) › [Language](index.md)

# Grouped imports cover several modules

Decision (user request: writing `import` and `from` on every line is repetitive and token hungry): `import (A, B from "a.ms", C from "b.ms")` imports from several modules in one statement. `ms fmt` merges consecutive imports into one group, one clause per line; a lone import and an import with a trailing comment stay as written.

Apply when: changing import syntax, the formatter's import handling, or anything keyed on an import's source position.
Evidence: [canonical rule](../../documentation/core-language/modules/declarations.md#names-and-declaration-order); parser and formatter tests in `crates/ms-syntax/tests/grouped_imports.rs`.
Verify: the parser expands a group into the flat import list, so the checker is unchanged. `Import.pos` is the statement keyword and `Import.clause` the clause start; removal fixes (unused import lint, redundant prelude import) work per clause and delete the whole statement only when every clause goes. The generic item layout must skip grouped imports, since it splits at commas inside a clause.
