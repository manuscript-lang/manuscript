[Wiki](../index.md) › [Runtime](index.md)

# Large write payloads take a pool permit before the copy

Verified: `/io` on the web benchmark (64 connections, 1 MiB write plus read) held one 1 MiB clone per in-flight request while only 4 pool threads ran jobs, so RSS reached about 90 MB after the load. Parking the caller in `pool::admit` before `data.clone()` (at most `threads()` permits, waiters on remote tokens, no polling) cut it to about 29 MB at the same 1.8k req/s. The permit is a `Closeable` (`WritePermit`) held by the promise's args, so a cancelled or dropped promise releases it.

Apply when: adding a pool-backed call that copies a large caller payload.
Evidence: [pool.rs](../../crates/ms-rt/src/glue/pool.rs), [fs.ms](../../stdlib/os/fs.ms), [fixture](../../tests/e2e/testdata/stdlib/fs-write-backpressure.ms).
Verify: run the fixture; compare RSS after `/io` load before and after.
