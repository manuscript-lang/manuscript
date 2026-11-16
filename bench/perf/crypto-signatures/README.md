# Signature and key-agreement speed

`ed25519.ms` runs 3000 rounds of `public_key`, `sign` and `verify`; `ecdsa.ms` runs 1000 rounds
of P-256 `ecdsa_sign`, `ecdsa_verify` and `ecdh_shared_secret`. `ed25519.go` and `ecdsa.go` are
the same loops with Go's `crypto` packages. Build the Manuscript programs with
`ms build bench/perf/crypto-signatures/<name>.ms -o /tmp/<name>` and the Go ones with `go build`
(after `go mod init x`). Compare speed with Go only.

## 2026-11-16, `main` 3b2ef968, Linux x86-64 (AVX2, SHA-NI), wall time of 3 runs

`ed25519-dalek`, `p256`, `p384` and `p521` were built with `default-features = false`, which
dropped their precomputed basepoint tables (`fast` on `ed25519-dalek`, `precomputed-tables`
on the curves). Every signature and public-key derivation then ran a variable-base multiply
(callgrind: 46% of the Ed25519 signing profile in `variable_base::mul`). `precomputed-tables` on the
`primeorder` curves needs `std` (they initialise the table lazily), so `p256`, `p384` and `p521`
also take `std`; the runtime archive is a std program already. The lock file gains dependency edges
(`getrandom`, `once_cell`) between crates it already holds and no new crate.

| Program | Before | After | Go 1.24.7 |
| --- | --- | --- | --- |
| `ed25519.ms` (3000 rounds) | 525 ms | 290 ms | 280 to 330 ms |
| `ed25519.ms`, `sign` alone (3000 calls) | 300 ms | 116 ms | 111 ms |
| `ecdsa.ms` (1000 rounds) | 1050 to 1180 ms | 630 to 700 ms | 170 to 190 ms |

Ed25519 matches Go. P-256 is still about 3.5x slower: verify and ECDH multiply an arbitrary
point, which no table covers, and the `p256` field multiply is portable code (`crypto-bigint`
Karatsuba, 56% of the remaining profile) where Go uses assembly. Closing that needs a specialised
field implementation, not a feature flag.

Other primitives measured the same day against Go (not changed): SHA-256 over 640 MB 480 ms
against 507 ms, PBKDF2-SHA-256 with 300000 iterations 55 against 73 ms, RSA-2048 key generation,
200 signs and 200 verifies 423 against 416 ms. Linked size of a program that uses Ed25519 or ECDSA
grows by about 12 KB and 268 KB respectively; programs that use neither are unchanged.
