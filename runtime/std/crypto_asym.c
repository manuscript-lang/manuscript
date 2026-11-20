/* @std/crypto asymmetric natives on libcrypto: ECDSA and ECDH over P-256, P-384 and P-521, X25519, and RSA (PKCS#1
   v1.5, PSS, OAEP). Keys are PKCS#8 private and PKIX public DER, parsed as Go's crypto/x509 does (the recorded Go
   oracle in tests/oracle/crypto_asym.tsv is the contract): only the first DER element is read, ECDSA public keys are
   uncompressed points in canonical encoding, RSA keys must validate and re-encode to the same bytes. */
#include <openssl/asn1.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/param_build.h>
#include <openssl/crypto.h>
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <openssl/obj_mac.h>
#include <openssl/pkcs12.h>
#include <openssl/rand.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>

#include "abi.h"
#include "ms_rt/crypto.h"

typedef enum { K_NONE, K_P256, K_P384, K_P521, K_X25519, K_ED25519, K_RSA } kind;

static const uint8_t *bytes_of(const msrt_vec *v) { return v->ptr ? v->ptr : (const uint8_t *)""; }

static const EVP_MD *md_of(int64_t index) {
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

static int digest_of(const EVP_MD *md, const msrt_vec *data, uint8_t *out, unsigned *n) {
    return EVP_Digest(bytes_of(data), data->len, out, n, md, NULL);
}

/* ---- fixed-shape curve25519 keys ----------------------------------------------------------------------------- */

static const uint8_t X25519_OID[3] = {0x2b, 0x65, 0x6e}, ED25519_OID[3] = {0x2b, 0x65, 0x70};

static void pkcs8_25519(const uint8_t oid[3], const uint8_t key[32], uint8_t out[48]) {
    static const uint8_t head[9] = {0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03};
    static const uint8_t mid[4] = {0x04, 0x22, 0x04, 0x20};
    memcpy(out, head, 9);
    memcpy(out + 9, oid, 3);
    memcpy(out + 12, mid, 4);
    memcpy(out + 16, key, 32);
}
static void spki_25519(const uint8_t oid[3], const uint8_t key[32], uint8_t out[44]) {
    static const uint8_t head[9] = {0x30, 0x2a, 0x30, 0x05, 0x06, 0x03};
    memcpy(out, head, 6);
    memcpy(out + 6, oid, 3);
    out[9] = 0x03, out[10] = 0x21, out[11] = 0x00;
    memcpy(out + 12, key, 32);
}

/* ---- parsing ------------------------------------------------------------------------------------------------- */

/* Go's parser ignores bytes after the first element: the length of the leading SEQUENCE, or 0 when malformed. */
static size_t first_element(const uint8_t *der, size_t n) {
    if (n < 2 || der[0] != 0x30) return 0;
    size_t len, hdr;
    if (der[1] < 0x80) {
        len = der[1], hdr = 2;
    } else {
        size_t k = der[1] & 0x7f;
        if (k < 1 || k > 4 || n < 2 + k) return 0;
        len = 0;
        for (size_t i = 0; i < k; i++) len = len << 8 | der[2 + i];
        hdr = 2 + k;
    }
    return len <= n - hdr ? hdr + len : 0;
}

static kind ec_kind(const EVP_PKEY *key) {
    char name[32];
    if (EVP_PKEY_get_group_name((EVP_PKEY *)key, name, sizeof name, NULL) != 1) return K_NONE;
    if (!strcmp(name, "prime256v1")) return K_P256;
    if (!strcmp(name, "secp384r1")) return K_P384;
    if (!strcmp(name, "secp521r1")) return K_P521;
    return K_NONE;
}

static int der_equal(unsigned char *got, int n, const uint8_t *der, size_t len) {
    int same = got && n >= 0 && (size_t)n == len && memcmp(got, der, len) == 0;
    OPENSSL_free(got);
    return same;
}

/* A PKCS#8 private key; *which says what it is. NULL when it is none of the supported kinds or fails Go's checks. */
static EVP_PKEY *parse_private(const msrt_vec *v, kind *which) {
    *which = K_NONE;
    size_t len = first_element(bytes_of(v), v->len);
    if (!len) return NULL;
    const uint8_t *der = v->ptr;
    if (len == 48) {
        uint8_t want[48], zero[32] = {0};
        for (int i = 0; i < 2; i++) {
            const uint8_t *oid = i ? ED25519_OID : X25519_OID;
            pkcs8_25519(oid, zero, want);
            if (memcmp(der, want, 16) == 0) {
                *which = i ? K_ED25519 : K_X25519;
                return EVP_PKEY_new_raw_private_key(i ? EVP_PKEY_ED25519 : EVP_PKEY_X25519, NULL, der + 16, 32);
            }
        }
    }
    const uint8_t *p = der;
    PKCS8_PRIV_KEY_INFO *info = d2i_PKCS8_PRIV_KEY_INFO(NULL, &p, (long)len);
    if (!info || (size_t)(p - der) != len) {
        PKCS8_PRIV_KEY_INFO_free(info);
        return NULL;
    }
    const ASN1_OBJECT *alg_oid = NULL;
    const void *param = NULL;
    int param_type = 0;
    const X509_ALGOR *alg = NULL;
    const uint8_t *inner = NULL;
    int inner_len = 0;
    EVP_PKEY *key = NULL;
    if (!PKCS8_pkey_get0(&alg_oid, &inner, &inner_len, &alg, info)) {
        PKCS8_PRIV_KEY_INFO_free(info);
        return NULL;
    }
    X509_ALGOR_get0(&alg_oid, &param_type, &param, alg);
    if (OBJ_obj2nid(alg_oid) == NID_X9_62_id_ecPublicKey) {
        /* Go reads the scalar alone and derives the public key; an embedded one is ignored, but the curve
           identifiers must name a supported curve. */
        int curve = param_type == V_ASN1_OBJECT ? OBJ_obj2nid(param) : NID_undef;
        const char *name = curve == NID_X9_62_prime256v1 ? "P-256" : curve == NID_secp384r1 ? "P-384" : curve == NID_secp521r1 ? "P-521" : NULL;
        *which = curve == NID_X9_62_prime256v1 ? K_P256 : curve == NID_secp384r1 ? K_P384 : curve == NID_secp521r1 ? K_P521 : K_NONE;
        /* ECPrivateKey ::= SEQUENCE { version INTEGER (1), privateKey OCTET STRING, ... } */
        const uint8_t *q = inner;
        size_t ilen = first_element(inner, (size_t)inner_len);
        if (name && ilen == (size_t)inner_len) {
            long seq_len = 0;
            int tag = 0, cls = 0;
            if (ASN1_get_object(&q, &seq_len, &tag, &cls, inner_len) == V_ASN1_CONSTRUCTED && tag == V_ASN1_SEQUENCE) {
                const uint8_t *end = q + seq_len;
                long l1 = 0, l2 = 0;
                int ok = ASN1_get_object(&q, &l1, &tag, &cls, (long)(end - q)) == 0 && tag == V_ASN1_INTEGER && l1 == 1 && q[0] == 1;
                q += ok ? l1 : 0;
                ok = ok && ASN1_get_object(&q, &l2, &tag, &cls, (long)(end - q)) == 0 && tag == V_ASN1_OCTET_STRING && l2 > 0 && l2 <= 66;
                BIGNUM *d = ok ? BN_bin2bn(q, (int)l2, NULL) : NULL;
                if (d) {
                    OSSL_PARAM_BLD *bld = OSSL_PARAM_BLD_new();
                    OSSL_PARAM *params = NULL;
                    /* the public point is d*G, computed here because fromdata does not derive it */
                    EC_GROUP *group = EC_GROUP_new_by_curve_name(curve);
                    EC_POINT *point = group ? EC_POINT_new(group) : NULL;
                    uint8_t pub[133];
                    size_t pub_len = 0;
                    if (point && EC_POINT_mul(group, point, d, NULL, NULL, NULL) == 1)
                        pub_len = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, pub, sizeof pub, NULL);
                    if (bld && pub_len && OSSL_PARAM_BLD_push_utf8_string(bld, OSSL_PKEY_PARAM_GROUP_NAME, name, 0) &&
                        OSSL_PARAM_BLD_push_BN(bld, OSSL_PKEY_PARAM_PRIV_KEY, d) &&
                        OSSL_PARAM_BLD_push_octet_string(bld, OSSL_PKEY_PARAM_PUB_KEY, pub, pub_len))
                        params = OSSL_PARAM_BLD_to_param(bld);
                    EC_POINT_free(point);
                    EC_GROUP_free(group);
                    EVP_PKEY_CTX *fc = params ? EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL) : NULL;
                    if (!fc || EVP_PKEY_fromdata_init(fc) != 1 || EVP_PKEY_fromdata(fc, &key, EVP_PKEY_KEYPAIR, params) != 1)
                        key = NULL;
                    EVP_PKEY_CTX_free(fc);
                    OSSL_PARAM_free(params);
                    OSSL_PARAM_BLD_free(bld);
                    BN_clear_free(d);
                }
            }
        }
        if (key) { /* the scalar must be in 1..n-1 */
            EVP_PKEY_CTX *check = EVP_PKEY_CTX_new(key, NULL);
            int valid = check && EVP_PKEY_private_check(check) == 1;
            EVP_PKEY_CTX_free(check);
            if (!valid) {
                EVP_PKEY_free(key);
                key = NULL;
            }
        }
        if (!key) *which = K_NONE;
        PKCS8_PRIV_KEY_INFO_free(info);
        return key;
    }
    key = EVP_PKCS82PKEY(info);
    PKCS8_PRIV_KEY_INFO_free(info);
    if (!key) return NULL;
    if (EVP_PKEY_get_base_id(key) == EVP_PKEY_RSA) {
        /* Go validates the key and its CRT values; a re-encode catches altered values. */
        EVP_PKEY_CTX *check = EVP_PKEY_CTX_new(key, NULL);
        int valid = check && EVP_PKEY_check(check) == 1;
        EVP_PKEY_CTX_free(check);
        PKCS8_PRIV_KEY_INFO *again = valid ? EVP_PKEY2PKCS8(key) : NULL;
        unsigned char *enc = NULL;
        int n = again ? i2d_PKCS8_PRIV_KEY_INFO(again, &enc) : -1;
        PKCS8_PRIV_KEY_INFO_free(again);
        if (der_equal(enc, n, der, len)) *which = K_RSA;
    }
    if (*which == K_NONE) {
        EVP_PKEY_free(key);
        return NULL;
    }
    return key;
}

static EVP_PKEY *parse_public(const msrt_vec *v, kind *which) {
    *which = K_NONE;
    const uint8_t *der = bytes_of(v);
    if (v->len == 44) {
        uint8_t want[44], zero[32] = {0};
        for (int i = 0; i < 2; i++) {
            spki_25519(i ? ED25519_OID : X25519_OID, zero, want);
            if (memcmp(der, want, 12) == 0) {
                *which = i ? K_ED25519 : K_X25519;
                return EVP_PKEY_new_raw_public_key(i ? EVP_PKEY_ED25519 : EVP_PKEY_X25519, NULL, der + 12, 32);
            }
        }
    }
    const uint8_t *p = der;
    EVP_PKEY *key = d2i_PUBKEY(NULL, &p, (long)v->len);
    if (!key || (size_t)(p - der) != v->len) {
        EVP_PKEY_free(key);
        return NULL;
    }
    unsigned char *enc = NULL;
    int n = i2d_PUBKEY(key, &enc);
    int canonical = der_equal(enc, n, der, v->len);
    int id = EVP_PKEY_get_base_id(key);
    if (canonical && id == EVP_PKEY_EC) *which = ec_kind(key);
    if (canonical && id == EVP_PKEY_RSA) *which = K_RSA;
    if (*which == K_NONE) {
        EVP_PKEY_free(key);
        return NULL;
    }
    return key;
}

static void put(msrt_vec *out, unsigned char *der, int n) {
    msrt_write_bytes(out, der, n > 0 ? (size_t)n : 0);
    OPENSSL_free(der);
}

/* ---- keys ---------------------------------------------------------------------------------------------------- */

uint8_t msstd_crypto_ecdsa_generate(int64_t curve, msrt_vec *out) {
    if (curve == 3) {
        uint8_t k[32], der[48];
        if (RAND_bytes(k, sizeof k) != 1) return STATUS_INVALID_INPUT;
        pkcs8_25519(X25519_OID, k, der);
        msrt_write_bytes(out, der, sizeof der);
        OPENSSL_cleanse(k, sizeof k);
        OPENSSL_cleanse(der, sizeof der);
        return STATUS_OK;
    }
    static const char *const names[] = {"P-256", "P-384", "P-521"};
    if (curve < 0 || curve > 2) return STATUS_INVALID_INPUT;
    EVP_PKEY *key = EVP_PKEY_Q_keygen(NULL, NULL, "EC", names[curve]);
    PKCS8_PRIV_KEY_INFO *info = key ? EVP_PKEY2PKCS8(key) : NULL;
    unsigned char *der = NULL;
    int n = info ? i2d_PKCS8_PRIV_KEY_INFO(info, &der) : -1;
    PKCS8_PRIV_KEY_INFO_free(info);
    EVP_PKEY_free(key);
    if (n <= 0) return STATUS_INVALID_INPUT;
    msrt_write_bytes(out, der, (size_t)n);
    OPENSSL_clear_free(der, (size_t)n);
    return STATUS_OK;
}

uint8_t msstd_crypto_rsa_generate(int64_t bits, msrt_vec *out) {
    if (bits < 2048 || bits > 8192) return STATUS_INVALID_INPUT;
    EVP_PKEY *key = EVP_PKEY_Q_keygen(NULL, NULL, "RSA", (size_t)bits);
    PKCS8_PRIV_KEY_INFO *info = key ? EVP_PKEY2PKCS8(key) : NULL;
    unsigned char *der = NULL;
    int n = info ? i2d_PKCS8_PRIV_KEY_INFO(info, &der) : -1;
    PKCS8_PRIV_KEY_INFO_free(info);
    EVP_PKEY_free(key);
    if (n <= 0) return STATUS_INVALID_INPUT;
    msrt_write_bytes(out, der, (size_t)n);
    OPENSSL_clear_free(der, (size_t)n);
    return STATUS_OK;
}

uint8_t msstd_crypto_public_key_der(const msrt_vec *private_key, msrt_vec *out) {
    kind which;
    EVP_PKEY *key = parse_private(private_key, &which);
    if (!key) return STATUS_INVALID_INPUT;
    if (which == K_X25519 || which == K_ED25519) {
        uint8_t pub[32], der[44];
        size_t n = sizeof pub;
        int ok = EVP_PKEY_get_raw_public_key(key, pub, &n) == 1;
        EVP_PKEY_free(key);
        if (!ok) return STATUS_INVALID_INPUT;
        spki_25519(which == K_X25519 ? X25519_OID : ED25519_OID, pub, der);
        msrt_write_bytes(out, der, sizeof der);
        return STATUS_OK;
    }
    unsigned char *der = NULL;
    int n = i2d_PUBKEY(key, &der);
    EVP_PKEY_free(key);
    if (n <= 0) return STATUS_INVALID_INPUT;
    put(out, der, n);
    return STATUS_OK;
}

/* ---- ECDSA and ECDH ------------------------------------------------------------------------------------------ */

uint8_t msstd_crypto_ecdsa_sign(const msrt_vec *private_key, int64_t alg, const msrt_vec *data, msrt_vec *out) {
    const EVP_MD *md = md_of(alg);
    if (!md) return STATUS_UNSUPPORTED;
    kind which;
    EVP_PKEY *key = parse_private(private_key, &which);
    if (!key || (which != K_P256 && which != K_P384 && which != K_P521)) {
        EVP_PKEY_free(key);
        return STATUS_INVALID_INPUT;
    }
    uint8_t digest[EVP_MAX_MD_SIZE], sig[160];
    unsigned dn = 0;
    size_t sn = sizeof sig;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
    int ok = digest_of(md, data, digest, &dn) && ctx && EVP_PKEY_sign_init(ctx) == 1 &&
             EVP_PKEY_sign(ctx, sig, &sn, digest, dn) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    if (!ok) return STATUS_INVALID_INPUT;
    msrt_write_bytes(out, sig, sn);
    return STATUS_OK;
}

uint8_t msstd_crypto_ecdsa_verify(const msrt_vec *public_key, int64_t alg, const msrt_vec *data, const msrt_vec *signature) {
    const EVP_MD *md = md_of(alg);
    kind which;
    EVP_PKEY *key = md ? parse_public(public_key, &which) : NULL;
    if (!key || (which != K_P256 && which != K_P384 && which != K_P521)) {
        EVP_PKEY_free(key);
        return 0;
    }
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned dn = 0;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
    int ok = digest_of(md, data, digest, &dn) && ctx && EVP_PKEY_verify_init(ctx) == 1 &&
             EVP_PKEY_verify(ctx, bytes_of(signature), signature->len, digest, dn) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    return (uint8_t)ok;
}

uint8_t msstd_crypto_ecdh_shared_secret(const msrt_vec *private_key, const msrt_vec *peer, msrt_vec *out) {
    kind mine, theirs;
    EVP_PKEY *a = parse_private(private_key, &mine), *b = parse_public(peer, &theirs);
    uint8_t secret[66];
    size_t n = sizeof secret;
    int ok = a && b && mine == theirs && mine != K_RSA && mine != K_ED25519;
    EVP_PKEY_CTX *ctx = ok ? EVP_PKEY_CTX_new(a, NULL) : NULL;
    ok = ok && ctx && EVP_PKEY_derive_init(ctx) == 1 && EVP_PKEY_derive_set_peer(ctx, b) == 1 &&
         EVP_PKEY_derive(ctx, secret, &n) == 1;
    if (ok && mine == K_X25519) { /* a low-order peer point yields an all-zero secret, which Go rejects */
        uint8_t any = 0;
        for (size_t i = 0; i < n; i++) any |= secret[i];
        ok = any != 0;
    }
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(a);
    EVP_PKEY_free(b);
    if (!ok) {
        OPENSSL_cleanse(secret, sizeof secret);
        return STATUS_INVALID_INPUT;
    }
    msrt_write_bytes(out, secret, n);
    OPENSSL_cleanse(secret, sizeof secret);
    return STATUS_OK;
}

/* ---- RSA ----------------------------------------------------------------------------------------------------- */

static EVP_PKEY *rsa_private(const msrt_vec *v) {
    kind which;
    EVP_PKEY *key = parse_private(v, &which);
    if (key && which != K_RSA) {
        EVP_PKEY_free(key);
        return NULL;
    }
    return key;
}

static EVP_PKEY *rsa_public(const msrt_vec *v) {
    kind which;
    EVP_PKEY *key = parse_public(v, &which);
    EVP_PKEY_CTX *check = key && which == K_RSA ? EVP_PKEY_CTX_new(key, NULL) : NULL;
    int valid = check && EVP_PKEY_public_check(check) == 1;
    EVP_PKEY_CTX_free(check);
    if (key && !valid) {
        EVP_PKEY_free(key);
        return NULL;
    }
    return key;
}

/* padding: 0 PKCS#1 v1.5, 1 PSS with a digest-sized salt. Signs the digest of data. */
static uint8_t rsa_sign_with(const msrt_vec *private_key, int64_t alg, const msrt_vec *data, int pss, msrt_vec *out) {
    const EVP_MD *md = md_of(alg);
    if (!md) return STATUS_UNSUPPORTED;
    EVP_PKEY *key = rsa_private(private_key);
    if (!key) return STATUS_INVALID_INPUT;
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned dn = 0;
    size_t sn = (size_t)EVP_PKEY_get_size(key);
    uint8_t *sig = msrt_alloc(sn);
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
    int ok = digest_of(md, data, digest, &dn) && ctx && EVP_PKEY_sign_init(ctx) == 1 &&
             EVP_PKEY_CTX_set_rsa_padding(ctx, pss ? RSA_PKCS1_PSS_PADDING : RSA_PKCS1_PADDING) == 1 &&
             EVP_PKEY_CTX_set_signature_md(ctx, md) == 1 &&
             (!pss || (EVP_PKEY_CTX_set_rsa_pss_saltlen(ctx, RSA_PSS_SALTLEN_DIGEST) == 1 &&
                       EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, md) == 1)) &&
             EVP_PKEY_sign(ctx, sig, &sn, digest, dn) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    if (!ok) {
        msrt_free(sig);
        return STATUS_INVALID_INPUT;
    }
    out->ptr = sig;
    out->len = out->cap = sn;
    return STATUS_OK;
}

static uint8_t rsa_verify_with(const msrt_vec *public_key, int64_t alg, const msrt_vec *data, const msrt_vec *signature,
                               int pss) {
    const EVP_MD *md = md_of(alg);
    EVP_PKEY *key = md ? rsa_public(public_key) : NULL;
    if (!key) return 0;
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned dn = 0;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
    int ok = digest_of(md, data, digest, &dn) && ctx && EVP_PKEY_verify_init(ctx) == 1 &&
             EVP_PKEY_CTX_set_rsa_padding(ctx, pss ? RSA_PKCS1_PSS_PADDING : RSA_PKCS1_PADDING) == 1 &&
             EVP_PKEY_CTX_set_signature_md(ctx, md) == 1 &&
             (!pss || (EVP_PKEY_CTX_set_rsa_pss_saltlen(ctx, RSA_PSS_SALTLEN_DIGEST) == 1 &&
                       EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, md) == 1)) &&
             EVP_PKEY_verify(ctx, bytes_of(signature), signature->len, digest, dn) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    return (uint8_t)ok;
}

uint8_t msstd_crypto_rsa_sign(const msrt_vec *k, int64_t alg, const msrt_vec *data, msrt_vec *out) {
    return rsa_sign_with(k, alg, data, 0, out);
}
uint8_t msstd_crypto_rsa_sign_pss(const msrt_vec *k, int64_t alg, const msrt_vec *data, msrt_vec *out) {
    return rsa_sign_with(k, alg, data, 1, out);
}
uint8_t msstd_crypto_rsa_verify(const msrt_vec *k, int64_t alg, const msrt_vec *data, const msrt_vec *sig) {
    return rsa_verify_with(k, alg, data, sig, 0);
}
uint8_t msstd_crypto_rsa_verify_pss(const msrt_vec *k, int64_t alg, const msrt_vec *data, const msrt_vec *sig) {
    return rsa_verify_with(k, alg, data, sig, 1);
}

/* OAEP with an empty label and the hash alg for both the label and MGF1. The first argument of encrypt is a public key
   (the Rust native named it private_key; the stdlib passes a public key). */
static EVP_PKEY_CTX *oaep_ctx(EVP_PKEY *key, const EVP_MD *md, int encrypt) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
    int ok = ctx && (encrypt ? EVP_PKEY_encrypt_init(ctx) : EVP_PKEY_decrypt_init(ctx)) == 1 &&
             EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_OAEP_PADDING) == 1 && EVP_PKEY_CTX_set_rsa_oaep_md(ctx, md) == 1 &&
             EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, md) == 1;
    if (!ok) {
        EVP_PKEY_CTX_free(ctx);
        return NULL;
    }
    return ctx;
}

uint8_t msstd_crypto_rsa_encrypt(const msrt_vec *public_key, int64_t alg, const msrt_vec *message, msrt_vec *out) {
    const EVP_MD *md = md_of(alg);
    if (!md) return STATUS_UNSUPPORTED;
    EVP_PKEY *key = rsa_public(public_key);
    if (!key) return STATUS_INVALID_INPUT;
    EVP_PKEY_CTX *ctx = oaep_ctx(key, md, 1);
    size_t n = (size_t)EVP_PKEY_get_size(key);
    uint8_t *buf = msrt_alloc(n);
    int ok = ctx && EVP_PKEY_encrypt(ctx, buf, &n, bytes_of(message), message->len) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    if (!ok) {
        msrt_free(buf);
        return STATUS_INVALID_INPUT;
    }
    out->ptr = buf;
    out->len = out->cap = n;
    return STATUS_OK;
}

uint8_t msstd_crypto_rsa_decrypt(const msrt_vec *private_key, int64_t alg, const msrt_vec *ciphertext, msrt_vec *out) {
    const EVP_MD *md = md_of(alg);
    if (!md) return STATUS_UNSUPPORTED;
    EVP_PKEY *key = rsa_private(private_key);
    if (!key) return STATUS_INVALID_INPUT;
    EVP_PKEY_CTX *ctx = oaep_ctx(key, md, 0);
    size_t n = (size_t)EVP_PKEY_get_size(key);
    uint8_t *buf = msrt_alloc(n);
    int ok = ctx && EVP_PKEY_decrypt(ctx, buf, &n, bytes_of(ciphertext), ciphertext->len) == 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(key);
    if (!ok) {
        msrt_free(buf);
        return STATUS_AUTHENTICATION_FAILED;
    }
    msrt_write_bytes(out, buf, n);
    OPENSSL_cleanse(buf, n);
    msrt_free(buf);
    return STATUS_OK;
}
