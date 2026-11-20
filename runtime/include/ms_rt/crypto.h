/* ms_rt/crypto.h: the @std/crypto natives (runtime/std/crypto.c and crypto_asym.c, on libcrypto). Fallible functions
 * return a status (0 ok, 1 InvalidInput, 9 Unsupported, 18 AuthenticationFailed) and write the Bytes result through
 * `out` only on success; `alg` is the HashAlgorithm case index. Symbols are listed in runtime/symbols/crypto.txt. */
#ifndef MS_RT_CRYPTO_H
#define MS_RT_CRYPTO_H

#include "ms_rt/base.h"

void msstd_crypto_digest(int64_t alg, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_hmac(int64_t alg, const MsVec *key, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_derive_key(int64_t alg, const MsVec *password, const MsVec *salt, int64_t iterations, int64_t length, MsVec *out);
uint8_t msstd_crypto_hkdf(int64_t alg, const MsVec *secret, const MsVec *salt, const MsVec *info, int64_t length, MsVec *out);
uint8_t msstd_crypto_constant_time_equal(const MsVec *left, const MsVec *right);
void *msstd_crypto_hasher_new(int64_t alg);
void *msstd_crypto_hmac_hasher_new(int64_t alg, const MsVec *key);
void msstd_crypto_hasher_update(void *handle, const MsVec *data);
void msstd_crypto_hasher_finish(void *handle, MsVec *out);
uint8_t msstd_crypto_seal(const MsVec *key, const MsVec *nonce, const MsVec *data, const MsVec *aad, MsVec *out);
uint8_t msstd_crypto_open(const MsVec *key, const MsVec *nonce, const MsVec *data, const MsVec *aad, MsVec *out);
uint8_t msstd_crypto_aes_ctr(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_aes_cbc_encrypt(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_aes_cbc_decrypt(const MsVec *key, const MsVec *iv, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_sign(const MsVec *seed, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_public_key(const MsVec *seed, MsVec *out);
uint8_t msstd_crypto_verify(const MsVec *key, const MsVec *data, const MsVec *signature);
uint8_t msstd_crypto_ecdsa_generate(int64_t curve, MsVec *out);
uint8_t msstd_crypto_rsa_generate(int64_t bits, MsVec *out);
uint8_t msstd_crypto_public_key_der(const MsVec *private_key, MsVec *out);
uint8_t msstd_crypto_ecdsa_sign(const MsVec *private_key, int64_t alg, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_ecdsa_verify(const MsVec *public_key, int64_t alg, const MsVec *data, const MsVec *signature);
uint8_t msstd_crypto_ecdh_shared_secret(const MsVec *private_key, const MsVec *peer, MsVec *out);
uint8_t msstd_crypto_rsa_sign(const MsVec *k, int64_t alg, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_rsa_sign_pss(const MsVec *k, int64_t alg, const MsVec *data, MsVec *out);
uint8_t msstd_crypto_rsa_verify(const MsVec *k, int64_t alg, const MsVec *data, const MsVec *sig);
uint8_t msstd_crypto_rsa_verify_pss(const MsVec *k, int64_t alg, const MsVec *data, const MsVec *sig);
uint8_t msstd_crypto_rsa_encrypt(const MsVec *public_key, int64_t alg, const MsVec *message, MsVec *out);
uint8_t msstd_crypto_rsa_decrypt(const MsVec *private_key, int64_t alg, const MsVec *ciphertext, MsVec *out);

#endif
