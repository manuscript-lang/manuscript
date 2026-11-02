[Wiki](../index.md) › [Runtime](index.md)

# BigInt power estimates do not prove a result fits

Verified: a `k`-bit nonzero magnitude raised to `e` needs at least `e * (k - 1) + 1` bits. This lower bound can reject oversized powers early, but passing it does not prove the result fits. Check the computed magnitude against the documented bit limit before returning success, including exponent one.

Apply when: changing BigInt arithmetic limits or replacing an exact result check with an estimate.
Evidence: [power implementation and boundary regression](../../crates/ms-std-bigint/src/lib.rs), [called source regression](../../tests/e2e/testdata/stdlib/bigint-power-limits.ms).
Verify: `2.pow(16777215)` succeeds, `2.pow(16777216)` returns `LimitExceeded`, and `(2^5592406 - 1)^3` also returns `LimitExceeded` despite passing the lower-bound check.
