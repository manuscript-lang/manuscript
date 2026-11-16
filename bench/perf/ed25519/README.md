# Ed25519 sign, verify and public key

`main.ms` runs 3000 rounds of `public_key`, `sign` and `verify` on one seed and a five-byte
message and prints a checksum; `main.go` is the same loop with Go's `crypto/ed25519`.
`ms build bench/perf/ed25519/main.ms -o /tmp/ed` and `go build` in the directory
(`go mod init x` first) give the two programs. Compare speed with Go only.

## 2026-11-16, `main` 3b2ef968, Linux x86-64 (AVX2, SHA-NI), median of 3 wall runs

`ed25519-dalek` was built without its `fast` feature, so `curve25519-dalek` had no
precomputed basepoint tables and every `sign` and `public_key` ran a variable-base
multiplication (callgrind: 46% in the AVX2 field multiply, `variable_base::mul` on the
signing path). Enabling `fast` in `crates/ms-std-crypto/Cargo.toml` fixes it.

| Program | Wall time | Signing path, 3000 `sign` calls alone |
| --- | --- | --- |
| Before (no `fast`) | 525 ms | 300 ms |
| After (`fast`) | 290 ms | 116 ms |
| Go 1.24.7 `crypto/ed25519` | 280 to 330 ms | 111 ms |

Linked size of a program that uses Ed25519 grows by about 12 KB; programs that do not use it
are unchanged.
