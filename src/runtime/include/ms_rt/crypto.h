/* ms_rt/crypto.h: the @std/crypto natives (src/runtime/std/crypto.c and crypto_asym.c, on libcrypto). Fallible functions
 * return a status (0 ok, 1 InvalidInput, 9 Unsupported, 18 AuthenticationFailed) and write the Bytes result through
 * `out` only on success; `alg` is the HashAlgorithm case index. Symbols are listed in src/runtime/symbols/crypto.txt. */
#ifndef MS_RT_CRYPTO_H
#define MS_RT_CRYPTO_H

#include "ms_rt/base.h"

/* ms-sig: msstd_crypto_digest(alg: i64, data: *const VecVal, out: *mut VecVal) @domain=cryptography */
void msstd_crypto_digest(int64_t alg, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_hmac(alg_index: i64, key: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_hmac(int64_t alg, const MsVec *key, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_derive_key(alg_index: i64, password: *const VecVal, salt: *const VecVal, iterations: i64, length: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_derive_key(int64_t alg, const MsVec *password, const MsVec *salt, int64_t iterations, int64_t length, MsVec *out);
/* ms-sig: msstd_crypto_hkdf(alg_index: i64, secret: *const VecVal, salt: *const VecVal, info: *const VecVal, length: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_hkdf(int64_t alg, const MsVec *secret, const MsVec *salt, const MsVec *info, int64_t length, MsVec *out);
/* ms-sig: msstd_crypto_constant_time_equal(left: *const VecVal, right: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_constant_time_equal(const MsVec *left, const MsVec *right);
/* ms-sig: msstd_crypto_hasher_new(alg: i64) -> *mut ObjCell<Hasher> @handle @domain=cryptography */
void *msstd_crypto_hasher_new(int64_t alg);
/* ms-sig: msstd_crypto_hmac_hasher_new(alg: i64, key: *const VecVal) -> *mut ObjCell<Hasher> @handle @domain=cryptography */
void *msstd_crypto_hmac_hasher_new(int64_t alg, const MsVec *key);
/* ms-sig: msstd_crypto_hasher_update(handle h: *mut ObjCell<Hasher>, data: *const VecVal) @domain=cryptography */
void msstd_crypto_hasher_update(void *handle, const MsVec *data);
/* ms-sig: msstd_crypto_hasher_finish(handle h: *mut ObjCell<Hasher>, out: *mut VecVal) @domain=cryptography */
void msstd_crypto_hasher_finish(void *handle, MsVec *out);
/* ms-sig: msstd_crypto_seal(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_seal(const MsVec *key, const MsVec *nonce, const MsVec *data, const MsVec *aad, MsVec *out);
/* ms-sig: msstd_crypto_open(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_open(const MsVec *key, const MsVec *nonce, const MsVec *data, const MsVec *aad, MsVec *out);
/* ms-sig: msstd_crypto_aes_ctr(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_ctr(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_aes_cbc_encrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_cbc_encrypt(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_aes_cbc_decrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_aes_cbc_decrypt(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_sign(seed: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_sign(const MsVec *seed, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_public_key(seed: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_public_key(const MsVec *seed, MsVec *out);
/* ms-sig: msstd_crypto_verify(key: *const VecVal, data: *const VecVal, signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_verify(const MsVec *key, const MsVec *data, const MsVec *signature);
/* ms-sig: msstd_crypto_ecdsa_generate(curve: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_generate(int64_t curve, MsVec *out);
/* ms-sig: msstd_crypto_rsa_generate(bits: i64, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_generate(int64_t bits, MsVec *out);
/* ms-sig: msstd_crypto_public_key_der(key: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_public_key_der(const MsVec *private_key, MsVec *out);
/* ms-sig: msstd_crypto_ecdsa_sign(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_sign(const MsVec *private_key, int64_t alg, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_ecdsa_verify(public_key: *const VecVal, alg_index: i64, data: *const VecVal, signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdsa_verify(const MsVec *public_key, int64_t alg, const MsVec *data, const MsVec *signature);
/* ms-sig: msstd_crypto_ecdh_shared_secret(private_key: *const VecVal, peer: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_ecdh_shared_secret(const MsVec *private_key, const MsVec *peer, MsVec *out);
/* ms-sig: msstd_crypto_rsa_sign(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_sign(const MsVec *k, int64_t alg, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_rsa_sign_pss(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_sign_pss(const MsVec *k, int64_t alg, const MsVec *data, MsVec *out);
/* ms-sig: msstd_crypto_rsa_verify(public_key: *const VecVal, alg_index: i64, data: *const VecVal, signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_verify(const MsVec *k, int64_t alg, const MsVec *data, const MsVec *sig);
/* ms-sig: msstd_crypto_rsa_verify_pss(public_key: *const VecVal, alg_index: i64, data: *const VecVal, signature: *const VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_verify_pss(const MsVec *k, int64_t alg, const MsVec *data, const MsVec *sig);
/* ms-sig: msstd_crypto_rsa_encrypt(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_encrypt(const MsVec *public_key, int64_t alg, const MsVec *message, MsVec *out);
/* ms-sig: msstd_crypto_rsa_decrypt(private_key: *const VecVal, alg_index: i64, data: *const VecVal, out: *mut VecVal) -> u8 @domain=cryptography */
uint8_t msstd_crypto_rsa_decrypt(const MsVec *private_key, int64_t alg, const MsVec *ciphertext, MsVec *out);

#endif
