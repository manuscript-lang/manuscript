[Wiki](../index.md) › [Runtime](index.md)

# BigInt, Decimal and time natives are C; only the zone database is still Rust

Verified: `runtime/std/bignum*.c` (hand-written limb arithmetic, no GMP), `bigint.c`, `decimal.c` and `time*.c` replace the Rust crates. `ms-decimal` stays for `ms-lower`'s literal folding. `crates/ms-std-time` is now only the jiff zone seam (`msstd_time_zone_info`, `msstd_time_zone_local_offset`, `local_zone`) and goes away when zones are read in C. UTC and `+hh:mm` zones resolve in C.

- Oracles, not hand checks: `runtime/tests/oracle/*_gen.py` write exact Python integers and `decimal` answers, and `time_golden.txt` is Go's `time`. A positive-only fuzz missed a sign bug in the divide-and-conquer `to_string`; the oracle's negative cases caught it.
- Decimal speed is in the small helpers: a Decimal operation costs a few bignum calls, so `ms_big_pow10` (table, not `pow`) and digit counting (divide a stack copy, not render a string) decided a 7x gap. Profile with `valgrind --tool=callgrind` before adding fast paths.
- A C fault needs frame pointers for the stack line fixtures expect: `cargo xtask runtime` passes `-fno-omit-frame-pointer`.
- Every std test links all of `runtime/std/*.c`, so a new cross-file seam needs weak stubs in `runtime/tests/fake_zone.h` or `fake_list.h`.

Apply when: changing bignum, Decimal or time natives, or porting the zone database.
Evidence: [bignum.h](../../runtime/std/bignum.h), [decimal.c](../../runtime/std/decimal.c), [time_zone.c](../../runtime/std/time_zone.c), [oracle](../../runtime/tests/oracle/).
Verify: `make c-test` passes (about 7,000 oracle cases) and `make conform` is unchanged.
