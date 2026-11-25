[Wiki](../index.md) › [Compiler and build](index.md)

# Checked Int arithmetic is language behavior

Decision: `Int` arithmetic faults on overflow (design contract). An optimizer may remove a check only with a proof that covers the whole result range (a literal divisor, an identity operand, a guarded counter step); unknown `+`, `-`, and `*` stay checked. Evaluate both operands even when the result is constant so effectful calls are preserved.

Measured 2026-11-12: speculating (vector overflow flag per chunk, scalar replay) loses to the scalar checked loop, and LLVM 23 vectorizes neither `with.overflow` reductions nor early-exit loops with stores. The lever is removing the check: the range pass treats an accumulator whose addends lie in `[-2^16, 2^16]` (a widened `UInt8`/`Int8`/`Int16`/`UInt16`, or a bounded value) as a bounded counter, so a byte sum is 5x faster ([proposal](../../proposals/checked-int-loops.md), [fixture](../../../tests/conformance/fixtures/e2e/accept/narrow-sums-keep-values.ms)).

Apply when: adding overflow-check elimination, bounds narrowing, or constant folding.
Evidence: [overflow faults](../../../tests/conformance/fixtures/e2e/accept/numeric-faults.ms), [bounded arithmetic](../../../tests/conformance/fixtures/e2e/accept/bounded-int-arithmetic.ms), [counter step](../../../tests/conformance/fixtures/e2e/accept/counter-steps-keep-overflow-faults.ms), [int identities](../../../tests/conformance/fixtures/e2e/accept/int-identities.ms).
Evidence: interpreter, native lowering, simplifier boundary regressions.
Evidence: simplifier and checked-CSE regressions, dominator-scoped value numbering.
Evidence: range analysis, saved-length regressions.
Evidence: [integer conversion regression](../../../tests/conformance/fixtures/e2e/accept/int-float32-rounding.ms), MIR conversion fixture.
Verify: both signed and unsigned integer conversions to `Float32` round directly to binary32. An intermediate binary64 conversion can erase which side of a midpoint a large integer is on; cover direct calls and bound conversion methods.
Evidence: backend settings and compile regression, profile options.
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform`.
Source-verified: LLVM address metadata uses modular offsets, independently of source checked arithmetic, so compiler code that tracks pointer offsets must negate and add with wrapping arithmetic; a host negation of the minimum `Int` must not trap in the compiler itself.
Verify: run `make conform`; preserve zero-divisor faults and the checked division overflow.
Verify: repeated checks across I/O and dominated blocks collapse; sibling checks, different operations, overflow and division faults keep their behavior.
Verify: nested replacement loops eliminate redundant bounds checks; shrinking and conditional replacement still fault at an invalid index.
Verify: run the source fixture in Debug and Release; both constant and variable conversions, both signs, and ties to even must agree.

Radix spellings must be normalized before checking decimal suffixes or exponent markers: `d`, `e`, and `E` are valid hexadecimal digits. Keep literal-context inference and constant-fault folding consistent with ordinary number inference. Cover `Int8` expressions containing `0x1d`/`0x1e`, negated hex literals, and hex zero divisors and list indexes (checker regressions, [native fixture](../../../tests/conformance/fixtures/e2e/accept/hex-literal-context.ms)).

Unary identity signs belong to literal trees too. Propagate sized context through `+`/`-` only when `literal_hint` proves a same-kind literal tree; never narrow a named value implicitly. Keep unsigned-negative and intermediate-overflow rejection and single-rounding Float32 behavior ([regression](../../../tests/conformance/fixtures/e2e/accept/unary-plus-literal-context.ms)).

Optional payload context must reach the same literal trees. Constructor argument probing can cache a default `Int` or `Float` before the sized payload is known; recheck only proven numeric literals when that cached type differs. Preserve intermediate-fault checks and one-layer wrapping (checker fixtures).

A sized result reports the type-range fault message, never a 64-bit overflow message: `UInt32 * UInt32` can overflow 64-bit signed before the type range (the Rust Cranelift backend multiplied in 64 bits and reported the wrong text; the LLVM emitter checks at the type's own width). Found by differential generation of every sized type across backends and profiles ([fixture](../../../tests/conformance/fixtures/e2e/accept/unsigned-multiply-fault-message.ms)).
