[Wiki](../index.md) › [Runtime](index.md)

# Crypto runs on libcrypto, and the recorded Go oracle is the contract

Verified (2026-11-20, Linux glibc and musl x86-64, OpenSSL 3.0 API): `src/runtime/std/crypto.c` (digests, HMAC, PBKDF2, HKDF, streaming hashers, AES-GCM, AES-CTR, AES-CBC, Ed25519) and `crypto_asym.c` (ECDSA, ECDH, X25519, RSA with PKCS#1 v1.5, PSS and OAEP) define every `msstd_crypto_*` symbol (`src/runtime/symbols/crypto.txt`, `ms_rt/crypto.h`). `src/runtime/tests/std_crypto*.c` replay `src/runtime/tests/oracle/crypto.tsv` and `crypto_asym.tsv` (4,322 cases recorded from Go) under ASan and UBSan in `make c-test`.

The Rust crates `ms-std-crypto` and `ms-std-regex` are deleted: every target takes the C natives, so there is no per-module selection left.

Go parity that OpenSSL does not give for free, each found by the oracle: only the first DER element of a key is read; an EC private key is read from the scalar alone and the public point is recomputed (an embedded one is ignored, but the curve OIDs must name P-256, P-384 or P-521); a public EC or RSA key must re-encode to the same DER; an RSA private key must pass `EVP_PKEY_check` and re-encode identically; an RSA public key must pass `EVP_PKEY_public_check` (even moduli fail at use); X25519 and Ed25519 keys have one fixed DER shape; an all-zero X25519 secret is refused; AES-CBC bad padding is one error (`AuthenticationFailed`) for every bad case.

Apply when: changing `src/runtime/std/crypto*.c`, accepting a new key shape, or porting the crate to another target. Verify: `make c-test`; `ms test tests/conformance/fixtures/e2e/stdlib/crypto*.ms jwt.ms hash.ms`.
