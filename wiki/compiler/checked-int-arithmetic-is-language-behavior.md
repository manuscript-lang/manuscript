[Wiki](../index.md) › [Compiler and build](index.md)

# Checked Int arithmetic is language behavior

Decision: `Int` arithmetic faults on overflow ([design contract](../../crates/DESIGN.md)). An optimizer may remove a check only with a proof that covers the whole result range (a literal divisor, an identity operand, a guarded counter step); unknown `+`, `-`, and `*` stay checked. Evaluate both operands even when the result is constant so effectful calls are preserved.

Apply when: adding overflow-check elimination, bounds narrowing, or constant folding.
Evidence: [overflow faults](../../tests/conformance/fixtures/e2e/accept/numeric-faults.ms), [bounded arithmetic](../../tests/conformance/fixtures/e2e/accept/bounded-int-arithmetic.ms), [counter step](../../tests/conformance/fixtures/e2e/accept/counter-steps-keep-overflow-faults.ms), [int identities](../../tests/conformance/fixtures/e2e/accept/int-identities.ms).
Evidence: [interpreter](../../crates/ms-mir/src/interp.rs), [native lowering](../../crates/ms-clif/src/lower.rs), [simplifier boundary regressions](../../crates/ms-mir/tests/opt_simplify.rs).
Evidence: [simplifier and checked-CSE regressions](../../crates/ms-mir/tests/opt_simplify.rs), [dominator-scoped value numbering](../../crates/ms-mir/src/opt/simplify.rs).
Evidence: [range analysis](../../crates/ms-mir/src/opt/range.rs), [saved-length regressions](../../crates/ms-mir/tests/opt_range.rs).
Evidence: [integer conversion regression](../../tests/conformance/fixtures/e2e/accept/int-float32-rounding.ms), [MIR conversion fixture](../../crates/ms-mir/tests/fixtures/int_to_float32.mir).
Verify: both signed and unsigned integer conversions to `Float32` round directly to binary32. An intermediate binary64 conversion can erase which side of a midpoint a large integer is on; cover direct calls and bound conversion methods.
Evidence: [backend settings and compile regression](../../crates/ms-clif/src/cg.rs), [profile options](../../crates/ms-clif/src/lib.rs).
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform`.
Source-verified: LLVM address metadata uses modular offsets, independently of source checked arithmetic. Negate a subtraction delta with `wrapping_neg`, matching the following `wrapping_add`; ordinary host negation of `i64::MIN` panics in overflow-checked compiler builds even without a known base because `Option::zip` evaluates its argument eagerly. The backend regression `subtraction_tracks_minimum_integer_offsets_without_overflow` covers ordinary and exclusive-pointer parameters, minimum and neighboring deltas, and cancellation back to the original address.
Verify: run `cargo test -p ms-mir --test it -- opt_simplify::`; preserve zero-divisor faults and the checked division overflow.
Verify: repeated checks across I/O and dominated blocks collapse; sibling checks, different operations, overflow and division faults keep their behavior.
Verify: nested replacement loops eliminate redundant bounds checks; shrinking and conditional replacement still fault at an invalid index.
Verify: run the source fixture in Debug and Release; both constant and variable conversions, both signs, and ties to even must agree.
Verify: `cargo nextest run -p ms-clif`; preserve the long-Debug-function allocator selection.

Radix spellings must be normalized before checking decimal suffixes or exponent markers: `d`, `e`, and `E` are valid hexadecimal digits. Keep literal-context inference and constant-fault folding consistent with ordinary number inference. Cover `Int8` expressions containing `0x1d`/`0x1e`, negated hex literals, and hex zero divisors and list indexes ([checker regressions](../../crates/ms-check/src/radix_literal_tests.rs), [native fixture](../../tests/conformance/fixtures/e2e/accept/hex-literal-context.ms)).

Unary identity signs belong to literal trees too. Propagate sized context through `+`/`-` only when `literal_hint` proves a same-kind literal tree; never narrow a named value implicitly. Keep unsigned-negative and intermediate-overflow rejection and single-rounding Float32 behavior ([regression](../../tests/conformance/fixtures/e2e/accept/unary-plus-literal-context.ms)).

Optional payload context must reach the same literal trees. Constructor argument probing can cache a default `Int` or `Float` before the sized payload is known; recheck only proven numeric literals when that cached type differs. Preserve intermediate-fault checks and one-layer wrapping ([checker fixtures](../../crates/ms-check/tests/optional_literal_context.rs)).
