+++
title = "Cryptography and randomness"
weight = 54
+++

# Cryptography and randomness

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/crypto.ms`

```text
fn constant_time_equal(left: Bytes, right: Bytes) -> Bool
fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) -> Result[Bytes, LibraryError]
fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, LibraryError]
fn open(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]
fn public_key(seed: Bytes) -> Result[Bytes, LibraryError]
fn seal(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]
fn sha256(data: Bytes) -> Bytes
fn sha384(data: Bytes) -> Bytes
fn sha512(data: Bytes) -> Bytes
fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, LibraryError]
fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool
```

Cryptographic transforms are pure; key/nonce generation uses the explicit Entropy root. SHA hashes and HMAC support SHA-256/384/512; unsupported HMAC algorithm names return Unsupported. Hashing checks cancellation between chunks.

Derive_key is PBKDF2-HMAC-SHA256, with positive iterations and length 1–1048576, and periodic cancellation checks. Salt/work factor are explicit application decisions; the function does not claim a password-storage policy. Seal/open use AES-256-GCM: key is 32 bytes, nonce 12 bytes, authentication tag 16 bytes. Seal returns ciphertext with appended tag; open never releases plaintext before authentication. Associated data must match exactly. Reusing a nonce for a key violates the caller's cryptographic contract and is not automatically detected. Invalid key/nonce sizes return InvalidInput; tampering/wrong key returns AuthenticationFailed.

Sign/public_key use a 32-byte Ed25519 seed; verify takes a 32-byte public key and signature Bytes, returning false for wrong key/signature lengths or invalid signatures. Generated key/seed material can come from Entropy. These APIs use Bytes explicitly rather than opaque key handles; garbage collection cannot promise zeroization of retained copies. No legacy weak algorithm menu, implicit cryptographic randomness, private-key diagnostic redaction, or certificate issuance is claimed. TLS verification belongs to Network.connect_tls and the HTTP client.
