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
export fn constant_time_equal(left: Bytes, right: Bytes) Bool:

# Derives a key with PBKDF2-HMAC-SHA-256 using the supplied iteration count and length.
export fn derive_key(
    password: Bytes,
    salt: Bytes,
    iterations: Int,
    length: Int
) Result[Bytes, CryptoError]:

# Computes an HMAC using exactly `sha256`, `sha384`, or `sha512` (case-sensitive).
# Other algorithms return CryptoError.Unsupported.
export fn hmac(key: Bytes, data: Bytes, algorithm: String) Result[Bytes, CryptoError]:

# Authenticates and decrypts a value produced by `seal` using AES-GCM.
export fn open(
    key: Bytes,
    nonce: Bytes,
    ciphertext: Bytes,
    associated_data: Bytes
) Result[Bytes, CryptoError]:

# Derives the Ed25519 public key corresponding to a 32-byte private seed.
export fn public_key(seed: Bytes) Result[Bytes, CryptoError]:

# Encrypts and authenticates plaintext with AES-GCM. The caller supplies a unique nonce.
export fn seal(
    key: Bytes,
    nonce: Bytes,
    plaintext: Bytes,
    associated_data: Bytes
) Result[Bytes, CryptoError]:

# Returns the SHA-256 digest of the input.
export fn sha256(data: Bytes) Bytes:

# Returns the SHA-384 digest of the input.
export fn sha384(data: Bytes) Bytes:

# Returns the SHA-512 digest of the input.
export fn sha512(data: Bytes) Bytes:

# Signs data with an Ed25519 private seed.
export fn sign(seed: Bytes, data: Bytes) Result[Bytes, CryptoError]:

# Verifies an Ed25519 signature with a public key.
export fn verify(key: Bytes, data: Bytes, signature: Bytes) Bool:

impl Error for CryptoError:
    # Returns a cryptography-prefixed diagnostic without exposing keys, plaintext or ciphertext.
    fn message() String:

# Selects a supported SHA-2 algorithm without a runtime string spelling check.
# Existing hash functions and hmac(algorithm: String) remain available.
export type HashAlgorithm:
    # SHA-256, producing a 32-byte digest or HMAC.
    case Sha256
    # SHA-384, producing a 48-byte digest or HMAC.
    case Sha384
    # SHA-512, producing a 64-byte digest or HMAC.
    case Sha512

impl HashAlgorithm:
    # Computes this algorithm's digest, checking cancellation between chunks.
    fn digest(data: Bytes) Bytes:

    # Computes HMAC with this algorithm and retains CryptoError results.
    fn hmac(key: Bytes, data: Bytes) Result[Bytes, CryptoError]:
