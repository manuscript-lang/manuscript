[Wiki](../index.md) › [Runtime](index.md)

# Host API names do not establish units or write guarantees

Verified (contracts from the retired runtime; re-check against `stdlib/*.ms` before relying on them): host uptime and Clock instants have different origins and domains (the raw `monotonic_time` was removed; use `time.monotonic()` for timing). FileHandle count-returning writes loop to complete the input, just like Unit-returning native stream writes. A count result does not imply partial success, and failures do not retain a prefix count.

Apply when: documenting host contracts or proposing typed time, flag, stream, or error adapters. Trace validator, conversion, and result code before inferring semantics from names or result shapes; retain explicit migration decisions for public replacements.
Evidence: [host contracts](../../stdlib/intrinsics.ms), [process accounting](../../stdlib/os/system.ms), [called host contracts](../../tests/e2e/testdata/stdlib/host-contracts.ms).
Verify: check multi-chunk byte counts, sequential/positional EOF, shared adapter close and concrete domain errors.

Descriptor writers must propagate native drain failures through `write`, `flush` and `close` (#3263). An automatic drain may already have discarded an unwritten suffix, so preserve its terminal error across later empty flushes and refuse further buffering. Exercise both sub-64-KiB buffered writes and automatic drains against an exited child; a successful queue operation alone does not prove delivery.
