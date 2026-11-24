[Wiki](../index.md) › [Language](index.md)

# `?` has one meaning, follows lexical scope, and grants no access

Decision (Chinmay): each operator has a single clear meaning. `?` returns from the enclosing function by lexical scoping, the same way everywhere. It grants no access of its own: the access of the result is inherited from the variable it is applied to, and defaults to `let` (an immutable binding).

For one wanted case, use `match` with `_` rather than new syntax. When existing constructs (`get_or`, `match` with `_`) work, add no syntax.

Apply when: changing how `?` unwraps Results and optionals, or proposing a new operator or shorthand.
Evidence: [pattern matching](../../../documentation/core-language/control-flow/pattern-matching.md).
Verify: a proposal or change to `?` keeps one meaning and does not add an access rule of its own.
