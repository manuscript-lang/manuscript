/* ms_rt/crypto.h: the @std/crypto natives (runtime/std/crypto.c and crypto_asym.c, on libcrypto). Fallible functions
 * return a status (0 ok, 1 InvalidInput, 9 Unsupported, 18 AuthenticationFailed) and write the Bytes result through
 * `out` only on success; `alg` is the HashAlgorithm case index. Symbols are listed in runtime/symbols/crypto.txt. */
#ifndef MS_RT_CRYPTO_H
#define MS_RT_CRYPTO_H

#include "ms_rt/base.h"

void msstd_crypto_digest(int64_t alg, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_hmac(int64_t alg, const ms_vec *key, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_derive_key(int64_t alg, const ms_vec *password, const ms_vec *salt, int64_t iterations, int64_t length, ms_vec *out);
uint8_t msstd_crypto_hkdf(int64_t alg, const ms_vec *secret, const ms_vec *salt, const ms_vec *info, int64_t length, ms_vec *out);
uint8_t msstd_crypto_constant_time_equal(const ms_vec *left, const ms_vec *right);
void *msstd_crypto_hasher_new(int64_t alg);
void *msstd_crypto_hmac_hasher_new(int64_t alg, const ms_vec *key);
void msstd_crypto_hasher_update(void *handle, const ms_vec *data);
void msstd_crypto_hasher_finish(void *handle, ms_vec *out);
uint8_t msstd_crypto_seal(const ms_vec *key, const ms_vec *nonce, const ms_vec *data, const ms_vec *aad, ms_vec *out);
uint8_t msstd_crypto_open(const ms_vec *key, const ms_vec *nonce, const ms_vec *data, const ms_vec *aad, ms_vec *out);
uint8_t msstd_crypto_aes_ctr(const ms_vec *key, const ms_vec *iv, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_aes_cbc_encrypt(const ms_vec *key, const ms_vec *iv, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_aes_cbc_decrypt(const ms_vec *key, const ms_vec *iv, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_sign(const ms_vec *seed, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_public_key(const ms_vec *seed, ms_vec *out);
uint8_t msstd_crypto_verify(const ms_vec *key, const ms_vec *data, const ms_vec *signature);
uint8_t msstd_crypto_ecdsa_generate(int64_t curve, ms_vec *out);
uint8_t msstd_crypto_rsa_generate(int64_t bits, ms_vec *out);
uint8_t msstd_crypto_public_key_der(const ms_vec *private_key, ms_vec *out);
uint8_t msstd_crypto_ecdsa_sign(const ms_vec *private_key, int64_t alg, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_ecdsa_verify(const ms_vec *public_key, int64_t alg, const ms_vec *data, const ms_vec *signature);
uint8_t msstd_crypto_ecdh_shared_secret(const ms_vec *private_key, const ms_vec *peer, ms_vec *out);
uint8_t msstd_crypto_rsa_sign(const ms_vec *k, int64_t alg, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_rsa_sign_pss(const ms_vec *k, int64_t alg, const ms_vec *data, ms_vec *out);
uint8_t msstd_crypto_rsa_verify(const ms_vec *k, int64_t alg, const ms_vec *data, const ms_vec *sig);
uint8_t msstd_crypto_rsa_verify_pss(const ms_vec *k, int64_t alg, const ms_vec *data, const ms_vec *sig);
uint8_t msstd_crypto_rsa_encrypt(const ms_vec *public_key, int64_t alg, const ms_vec *message, ms_vec *out);
uint8_t msstd_crypto_rsa_decrypt(const ms_vec *private_key, int64_t alg, const ms_vec *ciphertext, ms_vec *out);

#endif
