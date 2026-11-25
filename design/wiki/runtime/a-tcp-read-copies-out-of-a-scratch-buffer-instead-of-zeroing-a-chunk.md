[Wiki](../index.md) › [Runtime](index.md)

# A TCP read copies out of a scratch buffer instead of zeroing a chunk

Verified (perf bash, 2026-11-18): `Connection::read` used `vec![0u8; 65536]` per call, then truncated, so each read of an 11-byte message zeroed 64 KiB (80% of the connection storm's user instructions) and a parked read of an idle connection held the whole chunk. It now waits for readability, reads into a per-thread `SCRATCH` for one non-blocking attempt, and copies the message into a vector of its own length. The scratch is taken only inside the attempt closure, never across `try_wait_fd`, because a parked task would let another task on the thread find it empty and allocate a second one.

Small-message loopback echo went 316 to 225 ms (Go 226). Look for the same pattern (zeroed chunk, then `truncate`) in other readers before assuming a read is kernel bound: `valgrind --tool=callgrind` with `MS_THREADS=1` shows it at once. See [the results page](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-18-concurrency.md).
