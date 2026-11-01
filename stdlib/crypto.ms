import Bytes from "@std/bytes.ms"
import (
    msstd_crypto_constant_time_equal,
    msstd_crypto_verify,
    msstd_crypto_open,
    msstd_crypto_public_key,
    msstd_crypto_seal,
    msstd_crypto_sign,
    msstd_crypto_aes_ctr,
    msstd_crypto_aes_cbc_encrypt,
    msstd_crypto_aes_cbc_decrypt,
    msstd_crypto_ecdsa_generate,
    msstd_crypto_public_key_der,
    msstd_crypto_ecdsa_sign,
    msstd_crypto_ecdsa_verify,
    msstd_crypto_ecdh_shared_secret,
    msstd_crypto_rsa_generate,
    msstd_crypto_rsa_sign,
    msstd_crypto_rsa_verify,
    msstd_crypto_rsa_sign_pss,
    msstd_crypto_rsa_verify_pss,
    msstd_crypto_rsa_encrypt,
    msstd_crypto_rsa_decrypt,
    msstd_crypto_digest,
    msstd_crypto_hmac,
    msstd_crypto_derive_key,
    msstd_crypto_hkdf,
    msstd_crypto_hasher_new,
    msstd_crypto_hmac_hasher_new,
    msstd_crypto_hasher_update,
    msstd_crypto_hasher_finish
) from "@std/internal/crypto.ms"

extern type NativeHasher

impl Hasher for NativeHasher:
    fn update(data: Bytes) Unit:
        msstd_crypto_hasher_update(self, data)

    fn finish() Bytes:
        return msstd_crypto_hasher_finish(self)

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
    return msstd_crypto_constant_time_equal(left, right)

# Derives a key with PBKDF2-HMAC-SHA-256 using the supplied iteration count and length.
export fn derive_key(
    password: Bytes,
    salt: Bytes,
    iterations: Int,
    length: Int
) Bytes!CryptoError:
    return HashAlgorithm.Sha256.derive_key(password, salt, iterations, length)

# Authenticates and decrypts a value produced by `seal` using AES-GCM with a 16, 24 or 32-byte key.
export fn open(
    key: Bytes,
    nonce: Bytes,
    ciphertext: Bytes,
    associated_data: Bytes
) Bytes!CryptoError:
    return msstd_crypto_open(key, nonce, ciphertext, associated_data)

# Derives the Ed25519 public key corresponding to a 32-byte private seed.
export fn public_key(seed: Bytes) Bytes!CryptoError:
    return msstd_crypto_public_key(seed)

# Encrypts and authenticates plaintext with AES-GCM using a 16, 24 or 32-byte key and 12-byte nonce.
# The caller supplies a unique nonce.
export fn seal(
    key: Bytes,
    nonce: Bytes,
    plaintext: Bytes,
    associated_data: Bytes
) Bytes!CryptoError:
    return msstd_crypto_seal(key, nonce, plaintext, associated_data)

# Returns the SHA-256 digest of the input.
export fn sha256(data: Bytes) Bytes:
    return HashAlgorithm.Sha256.digest(data)

# Returns the SHA-384 digest of the input.
export fn sha384(data: Bytes) Bytes:
    return HashAlgorithm.Sha384.digest(data)

# Returns the SHA-512 digest of the input.
export fn sha512(data: Bytes) Bytes:
    return HashAlgorithm.Sha512.digest(data)

# Signs data with an Ed25519 private seed.
export fn sign(seed: Bytes, data: Bytes) Bytes!CryptoError:
    return msstd_crypto_sign(seed, data)

# Verifies an Ed25519 signature with a public key.
export fn verify(key: Bytes, data: Bytes, signature: Bytes) Bool:
    return msstd_crypto_verify(key, data, signature)

impl Error for CryptoError:
    # Returns a cryptography-prefixed diagnostic without exposing keys, plaintext or ciphertext.
    fn message() String:
        match self:
            InvalidInput: return "cryptography: invalid input"
            Unsupported: return "cryptography: operation not supported"
            AuthenticationFailed: return "cryptography: authentication failed"

# Selects an elliptic curve for ECDSA and ECDH keys.
export type Curve:
    # NIST P-256 (secp256r1).
    case P256
    # NIST P-384 (secp384r1).
    case P384
    # NIST P-521 (secp521r1).
    case P521
    # Curve25519, valid for key agreement (`ecdh_shared_secret`) only.
    case X25519

# Incrementally hashes or authenticates data supplied in chunks.
export interface Hasher:
    # Appends data to the running hash.
    fn update(data: Bytes) Unit
    # Returns the digest of all data supplied since creation or the last finish, then resets the state.
    fn finish() Bytes

# Encrypts or decrypts data with AES in CTR mode. The same call encrypts and decrypts.
# `key` is 16, 24 or 32 bytes and `iv` is the 16-byte initial counter block.
export fn aes_ctr(key: Bytes, iv: Bytes, data: Bytes) Bytes!CryptoError:
    return msstd_crypto_aes_ctr(key, iv, data)

# Encrypts with AES in CBC mode and PKCS#7 padding. `key` is 16, 24 or 32 bytes; `iv` is 16 bytes.
export fn aes_cbc_encrypt(key: Bytes, iv: Bytes, plaintext: Bytes) Bytes!CryptoError:
    return msstd_crypto_aes_cbc_encrypt(key, iv, plaintext)

# Decrypts AES-CBC data and removes PKCS#7 padding.
# Fails with InvalidInput for a bad key, IV or length, and AuthenticationFailed for invalid padding.
export fn aes_cbc_decrypt(key: Bytes, iv: Bytes, ciphertext: Bytes) Bytes!CryptoError:
    return msstd_crypto_aes_cbc_decrypt(key, iv, ciphertext)

# Generates a private key and returns it as PKCS#8 DER bytes.
export fn ecdsa_generate(curve: Curve) Bytes!CryptoError:
    return msstd_crypto_ecdsa_generate(curve)

# Returns the PKIX (SubjectPublicKeyInfo) DER public key for a PKCS#8 DER private key.
# Works for ECDSA, X25519, Ed25519 and RSA private keys.
export fn public_key_der(private_key: Bytes) Bytes!CryptoError:
    return msstd_crypto_public_key_der(private_key)

# Signs the digest of data with an ECDSA private key (PKCS#8 DER) and returns an ASN.1 DER signature.
export fn ecdsa_sign(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError:
    return msstd_crypto_ecdsa_sign(private_key, hash, data)

# Verifies an ASN.1 DER ECDSA signature with a PKIX DER public key. Malformed keys or signatures return False.
export fn ecdsa_verify(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool:
    return msstd_crypto_ecdsa_verify(public_key, hash, data, signature)

# Computes the shared secret between a PKCS#8 DER private key and a PKIX DER public key.
# Both keys must use the same curve (P-256, P-384, P-521 or X25519).
export fn ecdh_shared_secret(
    private_key: Bytes,
    peer_public_key: Bytes
) Bytes!CryptoError:
    return msstd_crypto_ecdh_shared_secret(private_key, peer_public_key)

# Generates an RSA private key of `bits` (2048 through 8192) as PKCS#8 DER bytes.
export fn rsa_generate(bits: Int) Bytes!CryptoError:
    return msstd_crypto_rsa_generate(bits)

# Signs the digest of data with RSASSA-PKCS1-v1_5 using a PKCS#8 DER RSA private key.
export fn rsa_sign(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError:
    return msstd_crypto_rsa_sign(private_key, hash, data)

# Verifies an RSASSA-PKCS1-v1_5 signature with a PKIX DER RSA public key.
export fn rsa_verify(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool:
    return msstd_crypto_rsa_verify(public_key, hash, data, signature)

# Signs the digest of data with RSASSA-PSS (salt length equal to the digest size).
export fn rsa_sign_pss(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError:
    return msstd_crypto_rsa_sign_pss(private_key, hash, data)

# Verifies an RSASSA-PSS signature produced with a digest-sized salt.
export fn rsa_verify_pss(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool:
    return msstd_crypto_rsa_verify_pss(public_key, hash, data, signature)

# Encrypts a short message with RSA-OAEP using the given hash and a PKIX DER public key.
export fn rsa_encrypt(
    public_key: Bytes,
    hash: HashAlgorithm,
    message: Bytes
) Bytes!CryptoError:
    return msstd_crypto_rsa_encrypt(public_key, hash, message)

# Decrypts an RSA-OAEP message with a PKCS#8 DER private key. Fails with AuthenticationFailed when decryption is rejected.
export fn rsa_decrypt(
    private_key: Bytes,
    hash: HashAlgorithm,
    ciphertext: Bytes
) Bytes!CryptoError:
    return msstd_crypto_rsa_decrypt(private_key, hash, ciphertext)

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
        return msstd_crypto_digest(self, data)

    # Computes HMAC with this algorithm and retains CryptoError results.
    fn hmac(key: Bytes, data: Bytes) Bytes!CryptoError:
        return msstd_crypto_hmac(self, key, data)

    # Derives a key with PBKDF2-HMAC using this algorithm, the iteration count and length.
    # Fails with InvalidInput for non-positive iterations or a length outside 1..1048576.
    fn derive_key(
        password: Bytes,
        salt: Bytes,
        iterations: Int,
        length: Int
    ) Bytes!CryptoError:
        return msstd_crypto_derive_key(self, password, salt, iterations, length)

    # Expands secret into length bytes with HKDF (RFC 5869) using this algorithm.
    # An empty salt uses the algorithm's zero-filled default. Fails with InvalidInput when
    # length is not positive or exceeds 255 times the digest size.
    fn hkdf(secret: Bytes, salt: Bytes, info: Bytes, length: Int) Bytes!CryptoError:
        return msstd_crypto_hkdf(self, secret, salt, info, length)

    # Creates an incremental hasher for this algorithm.
    fn hasher() Hasher:
        return msstd_crypto_hasher_new(self)

    # Creates an incremental HMAC with this algorithm and key.
    fn hmac_hasher(key: Bytes) Hasher:
        return msstd_crypto_hmac_hasher_new(self, key)
