[Wiki](../index.md) › [Language](index.md)

# Type aliases are transparent and resolved in the checker

Decision (Chinmay, 2026-11-11): the language gains `type Name[T] = Type`, any type expression, instead of magic compiler bounds such as a built-in `Numeric`. An alias is the same type as its target (no new nominal type), so the parser and checker treat it as a declaration that never reaches lowering: the checker (`src/compiler/check/resolve.c`) resolves a use by substituting the written arguments into the target resolved once over the alias's own variables.

Type sets (`type Number = Int | Float`) are bound-only: the checker represents one as a contract type tagged `Builtin::TypeSet` whose arguments are the members. `implements` admits a member, `numeric()` accepts a parameter whose set members are all numeric, and a literal `0` takes that parameter's type. Lowering narrows by the substituted type, so `Int8` instances still fault on overflow.

Apply when: adding another kind of declaration. Each `match` on `DeclKind` and `SymKind` needs the new arm; an alias is skipped by the signature pass and checked for exposed private types in `declaration_checks`.
Evidence: type_aliases tests, [accept fixture](../../../tests/lang/aliasing/type-alias.ms), [proposal](../../proposals/type-sets.md).
Verify: a cycle (`type A = B`, `type B = A`) reports once; `Rows` and `List[Row]` are interchangeable in arguments and bindings.

A method declared on a type-set receiver (`fn Ordered.min(other Self) Self`) is expanded by the checker into one `impl` per member, with fresh node ids. Copies must not share ids: per-node checker facts are concrete for a concrete receiver and would collide. The set must be declared in the same module; nested sets are not flattened.
