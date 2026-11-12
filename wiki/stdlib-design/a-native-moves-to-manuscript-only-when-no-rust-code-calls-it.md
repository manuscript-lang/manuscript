[Wiki](../index.md) › [Standard-library design](index.md)

# A native moves to Manuscript only when nothing calls it from Rust and a bench shows no loss

Verified (2026-11-11): `reverse_bits`, `reverse_bytes` and `filled` are `.ms` and measured faster than the natives (3.2 to 2.4 ns and 0.97 to 0.39 ns per op). Tried and reverted: BigInt `gcd`/`lcm`/`sqrt`/`inverse_mod` (22% to 41% slower than num-bigint's in-place code) and the float helpers `copy_sign`, `sign_bit`, `frexp`, `modf`, `next_after`, `round_to_even`, `is_integer` (each looked equal or faster alone, but 38% slower together in a loop, because pure natives inline into release code). Bench several together in a realistic loop, with the merge-base binary on the same machine, before keeping a port of a pure float or integer native.

Blockers found for other candidates: `crc32`/`adler32`/base64 are called by `ms-std-archive`, `ms-std-net` and TLS; glob by `ms-std-fs` walk; `msstd_url_parse` and `msstd_url_format` are called by name from `ms-lower/json.rs` (typed JSON of `Url`); Duration `+`/`-` and `5.seconds()` are lowered from `expr.rs`. Remove the Rust caller or lowering special case in the same change.

Apply when: choosing the next Rust native to port, or removing an `extern fn` from `stdlib/internal/*.ms`.
Evidence: [math.ms](../../stdlib/math/math.ms), [collections.ms](../../stdlib/collections/collections.ms), `grep -rn <symbol> crates` before porting.
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/numeric-helpers.ms` and `collections.ms` pass.
