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

# Authenticates and decrypts a value produced by `seal` using AES-GCM with a 16, 24 or 32-byte key.
export fn open(
    key: Bytes,
    nonce: Bytes,
    ciphertext: Bytes,
    associated_data: Bytes
) Result[Bytes, CryptoError]:

# Derives the Ed25519 public key corresponding to a 32-byte private seed.
export fn public_key(seed: Bytes) Result[Bytes, CryptoError]:

# Encrypts and authenticates plaintext with AES-GCM using a 16, 24 or 32-byte key and 12-byte nonce.
# The caller supplies a unique nonce.
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

# Selects a supported hash algorithm for digests, HMAC, PBKDF2 and HKDF.
# Md5 and Sha1 exist for interoperability with existing formats; prefer SHA-2 or SHA-3 for new designs.
export type HashAlgorithm:
    # MD5, producing a 16-byte digest or HMAC. Not collision resistant.
    case Md5
    # SHA-1, producing a 20-byte digest or HMAC. Not collision resistant.
    case Sha1
    # SHA-224, producing a 28-byte digest or HMAC.
    case Sha224
    # SHA-256, producing a 32-byte digest or HMAC.
    case Sha256
    # SHA-384, producing a 48-byte digest or HMAC.
    case Sha384
    # SHA-512, producing a 64-byte digest or HMAC.
    case Sha512
    # SHA3-256, producing a 32-byte digest or HMAC.
    case Sha3_256
    # SHA3-384, producing a 48-byte digest or HMAC.
    case Sha3_384
    # SHA3-512, producing a 64-byte digest or HMAC.
    case Sha3_512

impl HashAlgorithm:
    # Computes this algorithm's digest, checking cancellation between chunks.
    fn digest(data: Bytes) Bytes:

    # Computes HMAC with this algorithm and retains CryptoError results.
    fn hmac(key: Bytes, data: Bytes) Result[Bytes, CryptoError]:

    # Derives a key with PBKDF2-HMAC using this algorithm, the iteration count and length.
    # Fails with InvalidInput for non-positive iterations or a length outside 1..1048576.
    fn derive_key(
        password: Bytes,
        salt: Bytes,
        iterations: Int,
        length: Int
    ) Result[Bytes, CryptoError]:

    # Expands secret into length bytes with HKDF (RFC 5869) using this algorithm.
    # An empty salt uses the algorithm's zero-filled default. Fails with InvalidInput when
    # length is not positive or exceeds 255 times the digest size.
    fn hkdf(
        secret: Bytes,
        salt: Bytes,
        info: Bytes,
        length: Int
    ) Result[Bytes, CryptoError]:
