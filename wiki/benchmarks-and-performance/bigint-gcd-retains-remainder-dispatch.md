[Wiki](../index.md) › [Benchmarks and performance](index.md)

# BigInt GCD retains small-divisor remainder dispatch

Verified: a scalar Euclidean tail can remove repeated BigUint temporaries once the divisor fits `u64`, but the entry remainder must preserve `&BigUint % &BigUint`. In pinned num-bigint 0.5.1, this uses a remainder-only path for `u32` divisors; `&BigUint % u64` instead copies the dividend and computes a quotient. That overload change regressed a neighboring 32-bit-divisor control despite improving ordinary GCD.

Apply when: changing BigInt GCD, LCM, or remainder ownership/operand types.
Evidence: [GCD implementation and boundary test](../../crates/ms-std-bigint/src/lib.rs), [public performance controls](../../bench/perf/bigint-gcd/README.md).
Verify: compare zero/equal/reversed operands, exact divisibility and divisors immediately below/at/above `2^32` and `2^64`, alongside large/Fibonacci inputs. Blanket binary GCD also regressed small and unbalanced controls; a large-input win alone does not justify replacement.
