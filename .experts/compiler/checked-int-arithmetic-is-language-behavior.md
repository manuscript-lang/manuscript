[Wiki](../index.md) › [Compiler and build](index.md)

# Checked Int arithmetic is language behavior

Decision: `Int` arithmetic faults on overflow ([design contract](../../crates/DESIGN.md)). An optimizer may remove a check only with a proof that covers the whole result range (a literal divisor, an identity operand, a guarded counter step); unknown `+`, `-`, and `*` stay checked. Evaluate both operands even when the result is constant so effectful calls are preserved. A proof must be invalidated by every write to a cell it relies on, including peers modified in a loop body and closures, and must account for every loop prefix, not just the net delta.

Apply when: adding overflow-check elimination, bounds narrowing, or constant folding.
Evidence: [overflow faults](../../tests/e2e/testdata/accept/numeric-faults.ms), [bounded arithmetic](../../tests/e2e/testdata/accept/bounded-int-arithmetic.ms), [counter step](../../tests/e2e/testdata/accept/counter-steps-keep-overflow-faults.ms), [int identities](../../tests/e2e/testdata/accept/int-identities.ms).
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform`.

Verified: checked signed remainder differs from checked division at `MIN, -1`: remainder is zero while division faults. Constant folding must follow that distinction, and a variable numerator with divisor `-1` can fold to zero without removing evaluation of the numerator.
Evidence: [interpreter](../../crates/ms-mir/src/interp.rs), [native lowering](../../crates/ms-clif/src/lower.rs), [simplifier boundary regressions](../../crates/ms-mir/tests/opt_simplify.rs).
Verify: run `cargo test -p ms-mir --test opt_simplify`; preserve zero-divisor faults and the checked division overflow.

Verified: an identical checked scalar operation can reuse an earlier dominating result because reaching the second operation proves the first succeeded. Keep the first check and its source location, even if only the repeat's result is used. This belongs in dominator-scoped value numbering; declaring checked operations globally pure would also permit unsafe speculation.
Evidence: [simplifier and checked-CSE regressions](../../crates/ms-mir/tests/opt_simplify.rs), [dominator-scoped value numbering](../../crates/ms-mir/src/opt/simplify.rs).
Verify: repeated checks across I/O and dominated blocks collapse; sibling checks, different operations, overflow and division faults keep their behavior.

Verified: list element replacement preserves length across loop parameters only when every incoming list has the same length origin. Length equality does not establish element equality. Appending, shrinking, replacing a list, or reading it afresh from memory starts a new origin; propagating a saved length across those operations can incorrectly remove bounds checks.
Literal-list sizes also bound indices and fold length reads; a new list's capacity does not make its initial length nonzero. Negative indexing still requires its normalization unless non-negativity is proven.
Evidence: [range analysis](../../crates/ms-mir/src/opt/range.rs), [saved-length regressions](../../crates/ms-mir/tests/opt_range.rs).
Verify: nested replacement loops eliminate redundant bounds checks; shrinking and conditional replacement still fault at an invalid index.

Verified: an integer converted to `Float32` must round directly to binary32. Converting to binary64 first can discard the bit that decides which side of a binary32 midpoint the integer occupies: `4611686293305294849` must round up to `4611686568183201792`, while a binary64 intermediate incorrectly rounds down. Keep the target width through MIR, constant folding, and native code generation.
Evidence: [integer conversion regression](../../tests/e2e/testdata/accept/int-float32-rounding.ms), [MIR conversion fixture](../../crates/ms-mir/tests/fixtures/int_to_float32.mir).
Verify: run the source fixture in Debug and Release; both constant and variable conversions, both signs, and ties to even must agree.

Verified: Cranelift defaults its optimization level to `none`. Adding a conditional backend setting must preserve forwarding of the profile's `opt_level`; otherwise `speed` and `speed_and_size` silently stop applying. Validate the compile API with every supported level and a rejected unknown level, rather than testing only the new setting's selection predicate.
Evidence: [backend settings and compile regression](../../crates/ms-clif/src/cg.rs), [profile options](../../crates/ms-clif/src/lib.rs).
Verify: `cargo nextest run -p ms-clif`; preserve the long-Debug-function allocator selection.

---
Topics: [Testing](../topics/testing.md) · [Errors and results](../topics/errors-and-results.md)
