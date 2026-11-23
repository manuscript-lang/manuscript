/* runtime/std/crypto.h: the @std/crypto natives (src/runtime/std/crypto.c and crypto_asym.c, on libcrypto).
 * Fallible functions return a status (0 ok, 1 InvalidInput, 9 Unsupported, 18 AuthenticationFailed) and write
 * the Bytes result through `out` only on success; `alg` is the HashAlgorithm case index. Symbols are listed
 * in src/runtime/symbols/crypto.txt. */
#ifndef MS_RUNTIME_STD_CRYPTO_H
#define MS_RUNTIME_STD_CRYPTO_H

#include "base/bytes.h"
#include "abi/status.h"

/* ms-sig: msstd_crypto_digest(alg: i64, data: *const VecVal, out: *mut VecVal) @domain=cryptography */
void msstd_crypto_digest(int64_t alg, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_hmac(alg_index: i64, key: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8
 * @domain=cryptography */
uint8_t msstd_crypto_hmac(int64_t alg, const MsBytes *key, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_derive_key(alg_index: i64, password: *const VecVal, salt: *const VecVal, iterations:
 * i64, length: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_derive_key(int64_t alg, const MsBytes *password, const MsBytes *salt, int64_t iterations,
                                int64_t length, MsBytes *out);
/* ms-sig: msstd_crypto_hkdf(alg_index: i64, secret: *const VecVal, salt: *const VecVal, info: *const VecVal,
 * length: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_hkdf(int64_t alg, const MsBytes *secret, const MsBytes *salt, const MsBytes *info,
                          int64_t length, MsBytes *out);
/* ms-sig: msstd_crypto_constant_time_equal(left: *const VecVal, right: *const VecVal) -> u8
 * @domain=cryptography */
uint8_t msstd_crypto_constant_time_equal(const MsBytes *left, const MsBytes *right);
/* ms-sig: msstd_crypto_hasher_new(alg: i64) -> *mut ObjCell<Hasher> @domain=cryptography @end */
void *msstd_crypto_hasher_new(int64_t alg);
/* ms-sig: msstd_crypto_hmac_hasher_new(alg: i64, key: *const VecVal) -> *mut ObjCell<Hasher>
 * @domain=cryptography @end */
void *msstd_crypto_hmac_hasher_new(int64_t alg, const MsBytes *key);
/* ms-sig: msstd_crypto_hasher_update(handle h: *mut ObjCell<Hasher>, data: *const VecVal)
 * @domain=cryptography */
void msstd_crypto_hasher_update(void *handle, const MsBytes *data);
/* ms-sig: msstd_crypto_hasher_finish(handle h: *mut ObjCell<Hasher>, out: *mut VecVal) @domain=cryptography
 */
void msstd_crypto_hasher_finish(void *handle, MsBytes *out);
/* ms-sig: msstd_crypto_seal(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const
 * VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_seal(const MsBytes *key, const MsBytes *nonce, const MsBytes *data, const MsBytes *aad,
                          MsBytes *out);
/* ms-sig: msstd_crypto_open(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const
 * VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_open(const MsBytes *key, const MsBytes *nonce, const MsBytes *data, const MsBytes *aad,
                          MsBytes *out);
/* ms-sig: msstd_crypto_aes_ctr(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal)
 * -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_ctr(const MsBytes *key, const MsBytes *iv, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_aes_cbc_encrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_cbc_encrypt(const MsBytes *key, const MsBytes *iv, const MsBytes *data,
                                     MsBytes *out);
/* ms-sig: msstd_crypto_aes_cbc_decrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_cbc_decrypt(const MsBytes *key, const MsBytes *iv, const MsBytes *data,
                                     MsBytes *out);
/* ms-sig: msstd_crypto_sign(seed: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8
 * @domain=cryptography */
uint8_t msstd_crypto_sign(const MsBytes *seed, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_public_key(seed: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_public_key(const MsBytes *seed, MsBytes *out);
/* ms-sig: msstd_crypto_verify(key: *const VecVal, data: *const VecVal, signature: *const VecVal) -> u8
 * @domain=cryptography */
uint8_t msstd_crypto_verify(const MsBytes *key, const MsBytes *data, const MsBytes *signature);
/* ms-sig: msstd_crypto_ecdsa_generate(curve: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_generate(int64_t curve, MsBytes *out);
/* ms-sig: msstd_crypto_rsa_generate(bits: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_generate(int64_t bits, MsBytes *out);
/* ms-sig: msstd_crypto_public_key_der(key: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_public_key_der(const MsBytes *private_key, MsBytes *out);
/* ms-sig: msstd_crypto_ecdsa_sign(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_sign(const MsBytes *private_key, int64_t alg, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_ecdsa_verify(public_key: *const VecVal, alg_index: i64, data: *const VecVal,
 * signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_verify(const MsBytes *public_key, int64_t alg, const MsBytes *data,
                                  const MsBytes *signature);
/* ms-sig: msstd_crypto_ecdh_shared_secret(private_key: *const VecVal, peer: *const VecVal, out: *mut VecVal)
 * -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdh_shared_secret(const MsBytes *private_key, const MsBytes *peer, MsBytes *out);
/* ms-sig: msstd_crypto_rsa_sign(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_sign(const MsBytes *k, int64_t alg, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_rsa_sign_pss(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out:
 * *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_sign_pss(const MsBytes *k, int64_t alg, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_crypto_rsa_verify(public_key: *const VecVal, alg_index: i64, data: *const VecVal, signature:
 * *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_verify(const MsBytes *k, int64_t alg, const MsBytes *data, const MsBytes *sig);
/* ms-sig: msstd_crypto_rsa_verify_pss(public_key: *const VecVal, alg_index: i64, data: *const VecVal,
 * signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_verify_pss(const MsBytes *k, int64_t alg, const MsBytes *data, const MsBytes *sig);
/* ms-sig: msstd_crypto_rsa_encrypt(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_encrypt(const MsBytes *public_key, int64_t alg, const MsBytes *message,
                                 MsBytes *out);
/* ms-sig: msstd_crypto_rsa_decrypt(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut
 * VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_decrypt(const MsBytes *private_key, int64_t alg, const MsBytes *ciphertext,
                                 MsBytes *out);

#endif
