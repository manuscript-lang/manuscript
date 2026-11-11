[Wiki](../index.md) › [Language](index.md)

# Type aliases are transparent and resolved in the checker

Decision (Chinmay, 2026-11-11): the language gains `type Name[T] = Type`, any type expression, instead of magic compiler bounds such as a built-in `Numeric`. An alias is the same type as its target (no new nominal type), so the parser and checker treat it as a declaration that never reaches lowering: `ms-check` resolves a use in `resolve` by substituting the written arguments into the target resolved once over the alias's own variables (`alias_target`, `SymKind::Alias`).

Apply when: adding another kind of declaration. Each `match` on `DeclKind` and `SymKind` needs the new arm; an alias is skipped by the signature pass and checked for exposed private types in `declaration_checks`.
Evidence: [type_aliases tests](../../crates/ms-check/tests/type_aliases.rs), [accept fixture](../../tests/e2e/testdata/accept/type-alias.ms), [proposal](../../proposals/type-sets.md).
Verify: a cycle (`type A = B`, `type B = A`) reports once; `Rows` and `List[Row]` are interchangeable in arguments and bindings.
