[Wiki](../index.md) › [Standard-library design](index.md)

# A native moves to Manuscript only when no Rust code calls it

Verified (2026-11-11 audit): BigInt `gcd`, `lcm`, `sqrt`, `inverse_mod`, the float bit helpers (`copy_sign`, `sign_bit`, `frexp`, `modf`, `next_after`, `round_to_even`, `is_integer`, `reverse_bits`) and `filled` are `.ms` in `math.ms` and `collections.ms`. `pow_mod` stays native for Montgomery speed, `multiply_wide` and `ldexp` for exactness and speed.

Blockers found for the next movers: `crc32`/`adler32`/base64 are called by `ms-std-archive`, `ms-std-net` and TLS; glob by `ms-std-fs` walk; `msstd_url_parse` and `msstd_url_format` are called by name from `ms-lower/json.rs` (typed JSON of `Url`), and a `.ms` decoder needs a lowering hook first; Duration `+`/`-` and `5.seconds()` are lowered from `expr.rs`. Remove the Rust caller or the lowering special case in the same change, or the native has to stay.

Apply when: choosing the next Rust native to port, or removing an `extern fn` from `stdlib/internal/*.ms`.
Evidence: [math.ms](../../stdlib/math/math.ms), [collections.ms](../../stdlib/collections/collections.ms), `grep -rn <symbol> crates` before porting.
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/numeric-helpers.ms`, `numeric-wide.ms` and `collections.ms` pass.
