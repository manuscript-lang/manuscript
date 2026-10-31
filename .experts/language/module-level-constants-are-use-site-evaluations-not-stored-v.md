[Wiki](../index.md) › [Language](index.md)

# Module-level constants are use-site evaluations, not stored values

Decision: Chinmay approved top-level `let NAME[: T] = <constant expression>` in the #332 thread after the ban was found to have no recorded rationale; the gains of the ban were no module initialization order, no startup side effects, and no shared module state. Constants keep those gains: a use evaluates the initializer, so list and map constants are fresh per use.

Verified (design, from the retired implementation): a constant is a parameterless function whose body returns the initializer. The checker validates the constant-expression form, infers an unannotated type with cycle detection, and rewrites a constant name to a call; a written `NAME()` is rejected. Imports and exports are unchanged. Editor hover, completion, outline, symbols, semantic tokens, `ms inspect`, and docgen present a constant as a constant of its value type, not as a function.
Open: hoisting scalar constants to compile-time values for performance.

Apply when: changing top-level declarations, name resolution of module symbols, or the formatter's blank-line rules.
Evidence: [constants rules](../../documentation/core-language/modules/declarations.md#constants), [constant checking](../../crates/ms-check/src/constants.rs), and [constants fixture](../../tests/e2e/testdata/accept/constants.ms).
Verify: `ms run` on a module using an exported constant from another module, a local `let` shadowing a constant, and `A()` on a constant rejected.
