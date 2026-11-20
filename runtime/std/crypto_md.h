/* The OpenSSL digest of a @std/crypto HashAlgorithm, shared by the symmetric and asymmetric natives. */
#ifndef MS_STD_CRYPTO_MD_H
#define MS_STD_CRYPTO_MD_H

#include <stdint.h>

#include <openssl/evp.h>

/* The HashAlgorithm cases, in declaration order; NULL for an unknown index. */
static inline const EVP_MD *md_of(int64_t index) {
    switch (index) {
    case 0: return EVP_md5();
    case 1: return EVP_sha1();
    case 2: return EVP_sha224();
    case 3: return EVP_sha256();
    case 4: return EVP_sha384();
    case 5: return EVP_sha512();
    case 6: return EVP_sha3_256();
    case 7: return EVP_sha3_384();
    case 8: return EVP_sha3_512();
    default: return NULL;
    }
}

#endif
