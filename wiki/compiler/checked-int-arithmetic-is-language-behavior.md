[Wiki](../index.md) › [Compiler and build](index.md)

# Checked Int arithmetic is language behavior

Decision: `Int` arithmetic faults on overflow ([design contract](../../crates/DESIGN.md)). An optimizer may remove a check only with a proof that covers the whole result range (a literal divisor, an identity operand, a guarded counter step); unknown `+`, `-`, and `*` stay checked. Evaluate both operands even when the result is constant so effectful calls are preserved.

Apply when: adding overflow-check elimination, bounds narrowing, or constant folding.
Evidence: [overflow faults](../../tests/e2e/testdata/accept/numeric-faults.ms), [bounded arithmetic](../../tests/e2e/testdata/accept/bounded-int-arithmetic.ms), [counter step](../../tests/e2e/testdata/accept/counter-steps-keep-overflow-faults.ms), [int identities](../../tests/e2e/testdata/accept/int-identities.ms).
Evidence: [interpreter](../../crates/ms-mir/src/interp.rs), [native lowering](../../crates/ms-clif/src/lower.rs), [simplifier boundary regressions](../../crates/ms-mir/tests/opt_simplify.rs).
Evidence: [simplifier and checked-CSE regressions](../../crates/ms-mir/tests/opt_simplify.rs), [dominator-scoped value numbering](../../crates/ms-mir/src/opt/simplify.rs).
Evidence: [range analysis](../../crates/ms-mir/src/opt/range.rs), [saved-length regressions](../../crates/ms-mir/tests/opt_range.rs).
Evidence: [integer conversion regression](../../tests/e2e/testdata/accept/int-float32-rounding.ms), [MIR conversion fixture](../../crates/ms-mir/tests/fixtures/int_to_float32.mir).
Evidence: [backend settings and compile regression](../../crates/ms-clif/src/cg.rs), [profile options](../../crates/ms-clif/src/lib.rs).
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform`.
Verify: run `cargo test -p ms-mir --test opt_simplify`; preserve zero-divisor faults and the checked division overflow.
Verify: repeated checks across I/O and dominated blocks collapse; sibling checks, different operations, overflow and division faults keep their behavior.
Verify: nested replacement loops eliminate redundant bounds checks; shrinking and conditional replacement still fault at an invalid index.
Verify: run the source fixture in Debug and Release; both constant and variable conversions, both signs, and ties to even must agree.
Verify: `cargo nextest run -p ms-clif`; preserve the long-Debug-function allocator selection.
