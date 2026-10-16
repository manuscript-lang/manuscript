import Bytes from "@std/bytes.ms"

# Errors returned when cryptographic input is invalid or an algorithm is unavailable.
export type CryptoError:
    # Key/seed/nonce length, derivation iteration/count arguments or AES key size is invalid.
    case InvalidInput
    # The HMAC String selector is not exactly sha256, sha384 or sha512.
    case Unsupported
    # AES-GCM authentication failed, including a wrong key, nonce, associated data or altered ciphertext.
    case AuthenticationFailed

# Compares byte strings without making the comparison time depend on their contents.
export fn constant_time_equal(left: Bytes, right: Bytes) -> Bool:

# Derives a key with PBKDF2-HMAC-SHA-256 using the supplied iteration count and length.
export fn derive_key(
    password: Bytes,
    salt: Bytes,
    iterations: Int,
    length: Int
) -> Result[Bytes, CryptoError]:

# Computes an HMAC using exactly `sha256`, `sha384`, or `sha512` (case-sensitive).
# Other algorithms return CryptoError.Unsupported.
export fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, CryptoError]:

# Authenticates and decrypts a value produced by `seal` using AES-GCM.
export fn open(
    key: Bytes,
    nonce: Bytes,
    ciphertext: Bytes,
    associated_data: Bytes
) -> Result[Bytes, CryptoError]:

# Derives the Ed25519 public key corresponding to a 32-byte private seed.
export fn public_key(seed: Bytes) -> Result[Bytes, CryptoError]:

# Encrypts and authenticates plaintext with AES-GCM. The caller supplies a unique nonce.
export fn seal(
    key: Bytes,
    nonce: Bytes,
    plaintext: Bytes,
    associated_data: Bytes
) -> Result[Bytes, CryptoError]:

# Returns the SHA-256 digest of the input.
export fn sha256(data: Bytes) -> Bytes:

# Returns the SHA-384 digest of the input.
export fn sha384(data: Bytes) -> Bytes:

# Returns the SHA-512 digest of the input.
export fn sha512(data: Bytes) -> Bytes:

# Signs data with an Ed25519 private seed.
export fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, CryptoError]:

# Verifies an Ed25519 signature with a public key.
export fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool:

impl Error for CryptoError:
    # Returns a cryptography-prefixed diagnostic without exposing keys, plaintext or ciphertext.
    fn message() -> String:

# Selects a supported SHA-2 algorithm without a runtime string spelling check.
# Existing hash functions and hmac(algorithm: String) remain available.
export type HashAlgorithm:
    # SHA-256, producing a 32-byte digest or HMAC.
    case Sha256
    # SHA-384, producing a 48-byte digest or HMAC.
    case Sha384
    # SHA-512, producing a 64-byte digest or HMAC.
    case Sha512
    # Computes this algorithm's digest, checking cancellation between chunks.
    fn digest(data: Bytes) -> Bytes:
    # Computes HMAC with this algorithm and retains CryptoError results.
    fn hmac(key: Bytes, data: Bytes) -> Result[Bytes, CryptoError]:
# documentation documentation/standard-library/crypto.md
# +++
# title = "Cryptography and randomness"
# weight = 14
# +++
#
# # Cryptography and randomness
#
# API reference: [crypto](reference/crypto.md).
#
# Choose a cryptographic function by its purpose: hashing, keyed authentication, key derivation, encryption, or signatures. These transforms use supplied bytes. Random material comes from an explicit Entropy service.
#
# ## Choose the operation
#
# Cryptographic transforms are pure functions. Obtain random keys and nonces through an explicit `Entropy` service.
#
# | Task | Operation and algorithm |
# | --- | --- |
# | Hash bytes | `sha256`, `sha384`, or `sha512`. |
# | Authenticate bytes with a key | HMAC with the exact case-sensitive strings `sha256`, `sha384`, or `sha512`. Other names return `CryptoError.Unsupported`. |
# | Derive key bytes from a password | `derive_key`, using PBKDF2-HMAC-SHA256. |
# | Encrypt and authenticate | `seal` / `open`, using AES-256-GCM. |
# | Sign and verify | Ed25519 with `sign` / `verify`. |
#
# Hashing checks cancellation between chunks. Key derivation checks it periodically.
#
# ## Typed algorithm selection
#
# Use `HashAlgorithm.Sha256`, `Sha384`, or `Sha512` when the algorithm is chosen in source. Each value has `digest(data)` and `hmac(key, data)` operations. Algorithm case names are checked before execution; the methods use the existing hash/HMAC implementation and preserve cancellation and CryptoError results. Existing hash functions and string-based `hmac` remain available for runtime text configuration.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import HashAlgorithm from "@std/crypto.ms"
# import hex_encode from "@std/encoding.ms"
# import panic from "@std/faults.ms"
#
# test "select a typed SHA algorithm":
#     let digest = HashAlgorithm.Sha256.digest("abc".to_bytes())
#     if hex_encode(digest) != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad":
#         return panic("SHA-256 digest")
# ```
#
# ## Key derivation
#
# `derive_key` requires positive iterations and a length from 1 to 1048576. The application chooses the salt and work factor. The function does not define a password-storage policy.
#
# ## Authenticated encryption
#
# AES-256-GCM requires a 32-byte key and 12-byte nonce. `seal` appends a 16-byte authentication tag to the ciphertext. `open` authenticates before releasing any plaintext. The associated data must match exactly.
#
# A nonce must not be reused with the same key. The runtime does not detect that reuse. Invalid key or nonce sizes return `InvalidInput`; a wrong key or tampered ciphertext returns `AuthenticationFailed`.
#
# ## Signatures and key material
#
# `sign` and `public_key` take a 32-byte Ed25519 seed. `verify` takes a 32-byte public key and signature bytes. It returns false for invalid signatures or wrong key/signature lengths. Use `Entropy` to generate seed material.
#
# These APIs expose keys as `Bytes`, so garbage collection cannot guarantee erasure of retained copies. They provide no weak-algorithm menu, implicit randomness, automatic private-key diagnostic redaction, or certificate issuance. Verified TLS belongs to the Network and HTTP APIs.
# end-documentation
