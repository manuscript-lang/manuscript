[Wiki](../index.md) › [Runtime](index.md)

# Host API names do not establish units or write guarantees

Verified (contracts from the retired runtime; re-check against `stdlib/*.ms` before relying on them): `ProcessControl.monotonic_time` returns nanoseconds since runtime initialization and shares the process uptime origin; host uptime and Clock instants have different origins and domains. FileHandle count-returning writes loop to complete the input, just like Unit-returning native stream writes. A count result does not imply partial success, and failures do not retain a prefix count.

Apply when: documenting host contracts or proposing typed time, flag, stream, or error adapters. Trace validator, conversion, and result code before inferring semantics from names or result shapes; retain explicit migration decisions for public replacements.
Evidence: [host contracts](../../stdlib/intrinsics.ms), [process accounting](../../stdlib/os/process.ms), [called host contracts](../../tests/e2e/testdata/stdlib/host-contracts.ms).
Verify: bracket raw monotonic readings against elapsed nanoseconds; check multi-chunk byte counts, sequential/positional EOF, shared adapter close and concrete domain errors.
