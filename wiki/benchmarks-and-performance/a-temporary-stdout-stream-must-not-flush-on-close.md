[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A temporary `stdout()` stream must not flush on close

Verified (2026-11-07, `c18-cron-next-runs`): `stdout()` makes a stream per call and its drop closes the sink. While `Stdout.close` flushed, every `try stdout().write(...)` was a `write` system call (863k for 3 MB of input), and the program ran 2x slower than Rust when stdout was a pipe, although its instruction count matched Rust's. Making close a no-op took c18 from 1789 to 884 ms, c05 150 to 58, c09 128 to 59, c13 367 to 143.

Apply when: changing `Stdout` or the stream drop rules. Output must still be flushed at exit, on `flush()`, before spawning a child, before a stderr write and on a trap or fault (all already call `flush_stdout`). Measure with stdout piped to `cat` and compare `strace -c -f` write counts; a run with stdout on `/dev/null` hides the cost.
