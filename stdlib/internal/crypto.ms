import Bytes from "@std/bytes.ms"
import CryptoError, Curve, HashAlgorithm, NativeHasher from "@std/crypto.ms"

export extern fn msstd_crypto_constant_time_equal(left: Bytes, right: Bytes) Bool

export extern fn msstd_crypto_verify(key: Bytes, data: Bytes, signature: Bytes) Bool

export extern fn msstd_crypto_open(
    key: Bytes,
    nonce: Bytes,
    ciphertext: Bytes,
    associated_data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_public_key(seed: Bytes) Bytes!CryptoError

export extern fn msstd_crypto_seal(
    key: Bytes,
    nonce: Bytes,
    plaintext: Bytes,
    associated_data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_sign(seed: Bytes, data: Bytes) Bytes!CryptoError

export extern fn msstd_crypto_aes_ctr(
    key: Bytes,
    iv: Bytes,
    data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_aes_cbc_encrypt(
    key: Bytes,
    iv: Bytes,
    plaintext: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_aes_cbc_decrypt(
    key: Bytes,
    iv: Bytes,
    ciphertext: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_ecdsa_generate(curve: Curve) Bytes!CryptoError

export extern fn msstd_crypto_public_key_der(private_key: Bytes) Bytes!CryptoError

export extern fn msstd_crypto_ecdsa_sign(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_ecdsa_verify(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool

export extern fn msstd_crypto_ecdh_shared_secret(
    private_key: Bytes,
    peer_public_key: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_rsa_generate(bits: Int) Bytes!CryptoError

export extern fn msstd_crypto_rsa_sign(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_rsa_verify(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool

export extern fn msstd_crypto_rsa_sign_pss(
    private_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_rsa_verify_pss(
    public_key: Bytes,
    hash: HashAlgorithm,
    data: Bytes,
    signature: Bytes
) Bool

export extern fn msstd_crypto_rsa_encrypt(
    public_key: Bytes,
    hash: HashAlgorithm,
    message: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_rsa_decrypt(
    private_key: Bytes,
    hash: HashAlgorithm,
    ciphertext: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_digest(value: HashAlgorithm, data: Bytes) Bytes

export extern fn msstd_crypto_hmac(
    value: HashAlgorithm,
    key: Bytes,
    data: Bytes
) Bytes!CryptoError

export extern fn msstd_crypto_derive_key(
    value: HashAlgorithm,
    password: Bytes,
    salt: Bytes,
    iterations: Int,
    length: Int
) Bytes!CryptoError

export extern fn msstd_crypto_hkdf(
    value: HashAlgorithm,
    secret: Bytes,
    salt: Bytes,
    info: Bytes,
    length: Int
) Bytes!CryptoError

export extern fn msstd_crypto_hasher_new(alg: HashAlgorithm) NativeHasher

export extern fn msstd_crypto_hmac_hasher_new(
    alg: HashAlgorithm,
    key: Bytes
) NativeHasher

export extern fn msstd_crypto_hasher_update(hasher: NativeHasher, data: Bytes) Unit

export extern fn msstd_crypto_hasher_finish(hasher: NativeHasher) Bytes
