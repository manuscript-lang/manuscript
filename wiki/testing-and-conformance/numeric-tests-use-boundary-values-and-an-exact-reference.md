[Wiki](../index.md) › [Testing and conformance](index.md)

# Numeric tests use boundary values and an exact reference

Verified 2026-11-08: `@std/test/boundary.ms` supplies `int_boundaries`, `float_boundaries` and `finite_float_boundaries` (extremes and neighbors, ties, 2^53, subnormals, NaN, infinities), and `tests/conformance/fixtures/e2e/stdlib/numeric-reference-boundaries.ms` checks the public numeric stdlib against `BigInt`/`BigRat` references over them. It found no stdlib bug; the failures it raised were reference mistakes:

- `big_float_of_rat(x, 53).to_float()` rounds twice in the subnormal range; use `BigRat.to_float()` for a correctly rounded reference.
- `math.round` sends ties toward +infinity, `BigRat.round` away from zero.
- `Float.to_fixed` prints a negative value that rounds to zero as `-0`; `BigRat.to_fixed` drops the sign.
- `Decimal` keeps 34 significant digits, so an exact `BigInt` product is a reference only when it fits.
- `min`/`max` on Float follow the total order (NaN above all, ties return `left`, so signed zeros depend on argument order).

Apply when: adding or changing a numeric stdlib function; add its cases to that fixture, or call the helper from a new one.
Evidence: [helper](../../stdlib/test/boundary.ms), [fixture](../../tests/conformance/fixtures/e2e/stdlib/numeric-reference-boundaries.ms).
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/numeric-reference-boundaries.ms` reports 28 tests, 0 failed.

Decimal-exponent tests must distinguish malformed syntax from a valid magnitude beyond the parser's bound, including values beyond Int and former error sentinels. `parse_rat` once classified `-1000001` and Int-overflowing exponents as malformed; explicit Result propagation preserves `EOVERFLOW` versus `EBADMSG` (#3178). Check malformed suffixes after long digit sequences too, since magnitude alone must not hide a syntax error (`big-rat-exponent-errors.ms`).
