+++
title = "Cryptography and randomness"
weight = 14
+++

# Cryptography and randomness

API reference: [crypto](reference/crypto.md).

Choose a cryptographic function by its purpose: hashing, keyed authentication, key derivation, encryption, or signatures. These transforms use supplied bytes. Random material comes from an explicit Entropy service.

## Choose the operation

Cryptographic transforms are pure functions. Obtain random keys and nonces through an explicit `Entropy` service.

| Task | Operation and algorithm |
| --- | --- |
| Hash bytes | `sha256`, `sha384`, or `sha512`. |
| Authenticate bytes with a key | HMAC with SHA-256, SHA-384, or SHA-512. Unsupported algorithm names return `Unsupported`. |
| Derive key bytes from a password | `derive_key`, using PBKDF2-HMAC-SHA256. |
| Encrypt and authenticate | `seal` / `open`, using AES-256-GCM. |
| Sign and verify | Ed25519 with `sign` / `verify`. |

Hashing checks cancellation between chunks. Key derivation checks it periodically.

## Key derivation

`derive_key` requires positive iterations and a length from 1 to 1048576. The application chooses the salt and work factor. The function does not define a password-storage policy.

## Authenticated encryption

AES-256-GCM requires a 32-byte key and 12-byte nonce. `seal` appends a 16-byte authentication tag to the ciphertext. `open` authenticates before releasing any plaintext. The associated data must match exactly.

A nonce must not be reused with the same key. The runtime does not detect that reuse. Invalid key or nonce sizes return `InvalidInput`; a wrong key or tampered ciphertext returns `AuthenticationFailed`.

## Signatures and key material

`sign` and `public_key` take a 32-byte Ed25519 seed. `verify` takes a 32-byte public key and signature bytes. It returns false for invalid signatures or wrong key/signature lengths. Use `Entropy` to generate seed material.

These APIs expose keys as `Bytes`, so garbage collection cannot guarantee erasure of retained copies. They provide no weak-algorithm menu, implicit randomness, automatic private-key diagnostic redaction, or certificate issuance. Verified TLS belongs to the Network and HTTP APIs.
