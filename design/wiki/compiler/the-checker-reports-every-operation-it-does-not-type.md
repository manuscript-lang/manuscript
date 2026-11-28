[Wiki](../index.md) › [Compiler](index.md)

# The checker reports every operation it does not type

Verified (2026-11-28): the checker accepted `a < b` on any type, `-x` on any type, and any member of a function value or a bounded type variable, because those paths returned a type (or nothing) without reporting. Lowering then crashed (`icmp compares two ints`, `the checker recorded no usable call`). A silent return in the checker is a soundness hole: lowering is not a type checker.

Apply when: a checker path returns `MS_TY_NONE` or a fixed result type for an operand it did not classify, or skips `body_report_unknown_member`.
Evidence: `src/compiler/check/exprs_ops.c` (`ordering_type`, `body_unary`), `src/compiler/check/members.c`; fixtures `tests/diagnostics/types/ordering-requires-comparable.ms`, `unary-sign-requires-number.ms`, `tests/diagnostics/names/unknown-member-on-function-or-bounded-variable.ms`.
Verify: generate one program per type and operator; any program `ms check` accepts must also build. Ordering follows `Comparable`, so a type with its own `compare` orders and `true < false` does not.
