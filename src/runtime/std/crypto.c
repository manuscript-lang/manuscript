/* @std/crypto natives on OpenSSL's libcrypto (3.0 and later): digests, HMAC, PBKDF2, HKDF, AES-GCM, AES-CTR,
   AES-CBC and Ed25519. Every result is a Bytes value written as the runtime does; failures are status codes.
   Secrets are not logged and temporary key material is wiped with OPENSSL_cleanse. */
#include <limits.h>
#include <string.h>
#include <openssl/core_names.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <openssl/params.h>

#include "abi/status.h"
#include "base/alloc.h"
#include "base/desc.h"
#include "runtime/std/crypto.h"
#include "runtime/std/crypto_md.h"

static const char *md_name(int64_t index) {
  static const char *names[] = {"MD5",    "SHA1",     "SHA224",   "SHA256",  "SHA384",
                                "SHA512", "SHA3-256", "SHA3-384", "SHA3-512"};
  return index >= 0 && index < 9 ? names[index] : NULL;
}

static const uint8_t *bytes_of(const MsBytes *v) {
  return v->ptr ? v->ptr : (const uint8_t *)"";
}

/* ---- digests, HMAC, key derivation
 * --------------------------------------------------------------------------- */

void msstd_crypto_digest(int64_t alg, const MsBytes *data, MsBytes *out) {
  const EVP_MD *md = md_of(alg);
  uint8_t buf[EVP_MAX_MD_SIZE];
  unsigned n = 0;
  if (!md || !EVP_Digest(bytes_of(data), data->len, buf, &n, md, NULL)) {
    n = 0;
  }
  *(out) = ms_bytes_from_span(ms_span_of(buf, n));
}

uint8_t msstd_crypto_hmac(int64_t alg, const MsBytes *key, const MsBytes *data, MsBytes *out) {
  const EVP_MD *md = md_of(alg);
  if (!md) {
    return MS_STATUS_UNSUPPORTED;
  }
  uint8_t buf[EVP_MAX_MD_SIZE];
  size_t n = 0;
  if (!EVP_Q_mac(NULL, "HMAC", NULL, md_name(alg), NULL, bytes_of(key), key->len, bytes_of(data), data->len,
                 buf, sizeof buf, &n)) {
    return MS_STATUS_FAILED;
  }
  *(out) = ms_bytes_from_span(ms_span_of(buf, n));
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_derive_key(int64_t alg, const MsBytes *password, const MsBytes *salt, int64_t iterations,
                                int64_t length, MsBytes *out) {
  const EVP_MD *md = md_of(alg);
  if (!md) {
    return MS_STATUS_UNSUPPORTED;
  }
  if (iterations <= 0 || iterations > INT_MAX || length <= 0 || length > 1048576) {
    return MS_STATUS_INVALID_INPUT;
  }
  uint8_t *buf = ms_alloc((size_t)length);
  if (PKCS5_PBKDF2_HMAC((const char *)bytes_of(password), (int)password->len, bytes_of(salt), (int)salt->len,
                        (int)iterations, md, (int)length, buf) != 1) {
    OPENSSL_cleanse(buf, (size_t)length);
    ms_free(buf);
    return MS_STATUS_FAILED;
  }
  out->ptr = buf;
  out->len = out->cap = (size_t)length;
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_hkdf(int64_t alg, const MsBytes *secret, const MsBytes *salt, const MsBytes *info,
                          int64_t length, MsBytes *out) {
  const EVP_MD *md = md_of(alg);
  if (!md) {
    return MS_STATUS_UNSUPPORTED;
  }
  int64_t size = EVP_MD_get_size(md);
  if (length <= 0 || length > 255 * size) {
    return MS_STATUS_INVALID_INPUT;
  }
  /* Extract: PRK = HMAC(salt, secret); an empty salt is a block of zeros, which HMAC pads to anyway. */
  uint8_t zero[EVP_MAX_MD_SIZE] = {0}, prk[EVP_MAX_MD_SIZE], block[EVP_MAX_MD_SIZE];
  const uint8_t *salt_bytes = salt->len ? bytes_of(salt) : zero;
  size_t salt_len = salt->len ? salt->len : (size_t)size, prk_len = 0;
  if (!EVP_Q_mac(NULL, "HMAC", NULL, md_name(alg), NULL, salt_bytes, salt_len, bytes_of(secret), secret->len,
                 prk, sizeof prk, &prk_len)) {
    return MS_STATUS_FAILED;
  }
  /* Expand: T(i) = HMAC(PRK, T(i-1) || info || i). */
  uint8_t *buf = ms_alloc((size_t)length);
  size_t made = 0, prev = 0;
  uint8_t counter = 1;
  uint8_t *msg = ms_alloc((size_t)size + info->len + 1);
  int ok = 1;
  while (ok && made < (size_t)length) {
    memcpy(msg, block, prev);
    memcpy(msg + prev, bytes_of(info), info->len);
    msg[prev + info->len] = counter++;
    size_t n = 0;
    ok = EVP_Q_mac(NULL, "HMAC", NULL, md_name(alg), NULL, prk, prk_len, msg, prev + info->len + 1, block,
                   sizeof block, &n) != 0;
    prev = n;
    size_t take = (size_t)length - made < n ? (size_t)length - made : n;
    memcpy(buf + made, block, take);
    made += take;
  }
  OPENSSL_cleanse(prk, sizeof prk);
  OPENSSL_cleanse(block, sizeof block);
  ms_free(msg);
  if (!ok) {
    OPENSSL_cleanse(buf, (size_t)length);
    ms_free(buf);
    return MS_STATUS_FAILED;
  }
  out->ptr = buf;
  out->len = out->cap = (size_t)length;
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_constant_time_equal(const MsBytes *left, const MsBytes *right) {
  return left->len == right->len && (left->len == 0 || CRYPTO_memcmp(left->ptr, right->ptr, left->len) == 0);
}

/* ---- streaming digest and HMAC
 * ------------------------------------------------------------------------------- */

/* finish returns the output and resets to the initial state, so the initial state is kept beside the running
 * one. */
typedef struct {
  MsObj header;
  EVP_MD_CTX *md_init, *md_cur;
  EVP_MAC_CTX *mac_init, *mac_cur;
} MsHasher;

static void hasher_drop(MsObj *o) {
  MsHasher *h = (MsHasher *)o;
  EVP_MD_CTX_free(h->md_init);
  EVP_MD_CTX_free(h->md_cur);
  EVP_MAC_CTX_free(h->mac_init);
  EVP_MAC_CTX_free(h->mac_cur);
  ms_free(h);
}

static MsHasher *hasher_alloc(void) {
  MsHasher *h = ms_alloc(sizeof *h);
  memset(h, 0, sizeof *h);
  h->header.drop = hasher_drop;
  return h;
}

void *msstd_crypto_hasher_new(int64_t alg) {
  const EVP_MD *md = md_of(alg);
  MsHasher *h = hasher_alloc();
  h->md_init = EVP_MD_CTX_new();
  h->md_cur = EVP_MD_CTX_new();
  if (!md || !h->md_init || !h->md_cur || !EVP_DigestInit_ex(h->md_init, md, NULL) ||
      !EVP_MD_CTX_copy_ex(h->md_cur, h->md_init)) {
    hasher_drop(&h->header); /* an unknown algorithm index is a compiler bug; the handle is unusable */
    return NULL;
  }
  return h;
}

void *msstd_crypto_hmac_hasher_new(int64_t alg, const MsBytes *key) {
  const char *name = md_name(alg);
  MsHasher *h = hasher_alloc();
  EVP_MAC *mac = EVP_MAC_fetch(NULL, "HMAC", NULL);
  h->mac_init = mac ? EVP_MAC_CTX_new(mac) : NULL;
  EVP_MAC_free(mac);    /* the context keeps its own reference */
  char digest[16] = ""; /* the parameter wants a mutable string */
  if (name) {
    snprintf(digest, sizeof digest, "%s", name);
  }
  OSSL_PARAM params[2] = {OSSL_PARAM_construct_utf8_string(OSSL_MAC_PARAM_DIGEST, digest, 0),
                          OSSL_PARAM_construct_end()};
  const bool started = name && h->mac_init && EVP_MAC_init(h->mac_init, bytes_of(key), key->len, params);
  h->mac_cur = started ? EVP_MAC_CTX_dup(h->mac_init) : NULL;
  if (!h->mac_cur) {
    hasher_drop(&h->header);
    return NULL;
  }
  return h;
}

void msstd_crypto_hasher_update(void *handle, const MsBytes *data) {
  MsHasher *h = handle;
  if (!data->len) {
    return;
  }
  if (h->md_cur) {
    EVP_DigestUpdate(h->md_cur, data->ptr, data->len);
  } else {
    EVP_MAC_update(h->mac_cur, data->ptr, data->len);
  }
}

void msstd_crypto_hasher_finish(void *handle, MsBytes *out) {
  MsHasher *h = handle;
  uint8_t buf[EVP_MAX_MD_SIZE];
  size_t n = 0;
  if (h->md_cur) {
    unsigned len = 0;
    EVP_DigestFinal_ex(h->md_cur, buf, &len);
    n = len;
    EVP_MD_CTX_copy_ex(h->md_cur, h->md_init);
  } else {
    EVP_MAC_final(h->mac_cur, buf, &n, sizeof buf);
    EVP_MAC_CTX_free(h->mac_cur);
    h->mac_cur = EVP_MAC_CTX_dup(h->mac_init);
  }
  *(out) = ms_bytes_from_span(ms_span_of(buf, n));
}

/* ---- AES
 * ----------------------------------------------------------------------------------------------------- */

static int key_ok(const MsBytes *key) {
  return key->len == 16 || key->len == 24 || key->len == 32;
}

static const EVP_CIPHER *aes(const char *mode, size_t key_len) {
  static const char *const gcm[] = {"AES-128-GCM", "AES-192-GCM", "AES-256-GCM"};
  static const char *const ctr[] = {"AES-128-CTR", "AES-192-CTR", "AES-256-CTR"};
  static const char *const cbc[] = {"AES-128-CBC", "AES-192-CBC", "AES-256-CBC"};
  size_t k = 2;
  if (key_len == 16) {
    k = 0;
  }
  if (key_len == 24) {
    k = 1;
  }
  const char *const *names = cbc;
  if (mode[0] == 'g') {
    names = gcm;
  }
  if (mode[0] == 't') {
    names = ctr;
  }
  return EVP_get_cipherbyname(names[k]);
}

enum { TAG = 16 };

uint8_t msstd_crypto_seal(const MsBytes *key, const MsBytes *nonce, const MsBytes *data, const MsBytes *aad,
                          MsBytes *out) {
  if (!key_ok(key) || nonce->len != 12 || (uint64_t)data->len > ((1ull << 32) - 2) * 16) {
    return MS_STATUS_INVALID_INPUT;
  }
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  uint8_t *buf = ms_alloc(data->len + TAG);
  int n = 0, total = 0,
      ok = ctx && EVP_EncryptInit_ex(ctx, aes("g", key->len), NULL, bytes_of(key), bytes_of(nonce));
  if (ok && aad->len) {
    ok = EVP_EncryptUpdate(ctx, NULL, &n, aad->ptr, (int)aad->len);
  }
  if (ok && data->len) {
    ok = EVP_EncryptUpdate(ctx, buf, &n, data->ptr, (int)data->len);
    total = n;
  }
  if (ok) {
    ok = EVP_EncryptFinal_ex(ctx, buf + total, &n);
  }
  if (ok) {
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, TAG, buf + data->len);
  }
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) {
    ms_free(buf);
    return MS_STATUS_INVALID_INPUT;
  }
  out->ptr = buf;
  out->len = out->cap = data->len + TAG;
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_open(const MsBytes *key, const MsBytes *nonce, const MsBytes *data, const MsBytes *aad,
                          MsBytes *out) {
  if (!key_ok(key) || nonce->len != 12) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (data->len < TAG) {
    return MS_STATUS_AUTHENTICATION_FAILED;
  }
  size_t len = data->len - TAG;
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  uint8_t *buf = ms_alloc(len ? len : 1);
  int n = 0, total = 0,
      ok = ctx && EVP_DecryptInit_ex(ctx, aes("g", key->len), NULL, bytes_of(key), bytes_of(nonce));
  if (ok && aad->len) {
    ok = EVP_DecryptUpdate(ctx, NULL, &n, aad->ptr, (int)aad->len);
  }
  uint8_t tag[TAG] = {0}; /* OpenSSL takes the tag through a mutable pointer, so it gets a copy */
  memcpy(tag, (const uint8_t *)data->ptr + len, TAG);
  if (ok && len) {
    ok = EVP_DecryptUpdate(ctx, buf, &n, data->ptr, (int)len);
    total = n;
  }
  if (ok) {
    ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, TAG, tag);
  }
  if (ok) {
    ok = EVP_DecryptFinal_ex(ctx, buf + total, &n) > 0;
  }
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) {
    OPENSSL_cleanse(buf, len ? len : 1);
    ms_free(buf);
    return MS_STATUS_AUTHENTICATION_FAILED;
  }
  if (len) {
    out->ptr = buf;
    out->len = out->cap = len;
  } else {
    ms_free(buf);
    *(out) = (MsBytes){0};
  }
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_aes_ctr(const MsBytes *key, const MsBytes *iv, const MsBytes *data, MsBytes *out) {
  if (!key_ok(key) || iv->len != 16) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (!data->len) {
    return *(out) = (MsBytes){0}, MS_STATUS_OK;
  }
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  uint8_t *buf = ms_alloc(data->len);
  int n = 0, ok = ctx && EVP_EncryptInit_ex(ctx, aes("t", key->len), NULL, bytes_of(key), bytes_of(iv));
  for (size_t at = 0; ok && at < data->len;) { /* the API takes int lengths */
    size_t take = data->len - at > (1u << 30) ? (1u << 30) : data->len - at;
    ok = EVP_EncryptUpdate(ctx, buf + at, &n, (const uint8_t *)data->ptr + at, (int)take);
    at += take;
  }
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) {
    ms_free(buf);
    return MS_STATUS_FAILED;
  }
  out->ptr = buf;
  out->len = out->cap = data->len;
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_aes_cbc_encrypt(const MsBytes *key, const MsBytes *iv, const MsBytes *data,
                                     MsBytes *out) {
  if (!key_ok(key) || iv->len != 16) {
    return MS_STATUS_INVALID_INPUT;
  }
  size_t total_len = data->len + (16 - data->len % 16);
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  uint8_t *buf = ms_alloc(total_len);
  int n = 0, total = 0,
      ok = ctx && EVP_EncryptInit_ex(ctx, aes("c", key->len), NULL, bytes_of(key), bytes_of(iv));
  for (size_t at = 0; ok && at < data->len;) {
    size_t take = data->len - at > (1u << 30) ? (1u << 30) : data->len - at;
    ok = EVP_EncryptUpdate(ctx, buf + total, &n, (const uint8_t *)data->ptr + at, (int)take);
    total += n;
    at += take;
  }
  if (ok) {
    ok = EVP_EncryptFinal_ex(ctx, buf + total, &n);
  }
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) {
    ms_free(buf);
    return MS_STATUS_FAILED;
  }
  out->ptr = buf;
  out->len = out->cap = total_len;
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_aes_cbc_decrypt(const MsBytes *key, const MsBytes *iv, const MsBytes *data,
                                     MsBytes *out) {
  if (!key_ok(key) || iv->len != 16 || data->len == 0 || data->len % 16) {
    return MS_STATUS_INVALID_INPUT;
  }
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  uint8_t *buf = ms_alloc(data->len);
  int n = 0, total = 0,
      ok = ctx && EVP_DecryptInit_ex(ctx, aes("c", key->len), NULL, bytes_of(key), bytes_of(iv));
  if (ok) {
    EVP_CIPHER_CTX_set_padding(ctx,
                               0); /* the padding is checked here, to return one error for every bad case */
  }
  for (size_t at = 0; ok && at < data->len;) {
    size_t take = data->len - at > (1u << 30) ? (1u << 30) : data->len - at;
    ok = EVP_DecryptUpdate(ctx, buf + total, &n, (const uint8_t *)data->ptr + at, (int)take);
    total += n;
    at += take;
  }
  if (ok) {
    ok = EVP_DecryptFinal_ex(ctx, buf + total, &n);
  }
  EVP_CIPHER_CTX_free(ctx);
  size_t pad = ok ? buf[data->len - 1] : 0;
  int good = ok && pad != 0 && pad <= 16 && pad <= data->len;
  for (size_t i = 0; good && i < pad; i++) {
    good = buf[data->len - 1 - i] == pad;
  }
  if (!good) {
    OPENSSL_cleanse(buf, data->len);
    ms_free(buf);
    return ok ? MS_STATUS_AUTHENTICATION_FAILED : MS_STATUS_FAILED;
  }
  size_t len = data->len - pad;
  if (len) {
    out->ptr = buf;
    out->len = out->cap = len;
  } else {
    ms_free(buf);
    *(out) = (MsBytes){0};
  }
  return MS_STATUS_OK;
}

/* ---- Ed25519
 * ------------------------------------------------------------------------------------------------- */

uint8_t msstd_crypto_sign(const MsBytes *seed, const MsBytes *data, MsBytes *out) {
  if (seed->len != 32) {
    return MS_STATUS_INVALID_INPUT;
  }
  EVP_PKEY *key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed->ptr, 32);
  EVP_MD_CTX *ctx = key ? EVP_MD_CTX_new() : NULL;
  uint8_t sig[64];
  size_t n = sizeof sig;
  int ok = ctx && EVP_DigestSignInit(ctx, NULL, NULL, NULL, key) &&
           EVP_DigestSign(ctx, sig, &n, bytes_of(data), data->len);
  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(key);
  if (!ok) {
    return MS_STATUS_INVALID_INPUT;
  }
  *(out) = ms_bytes_from_span(ms_span_of(sig, n));
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_public_key(const MsBytes *seed, MsBytes *out) {
  if (seed->len != 32) {
    return MS_STATUS_INVALID_INPUT;
  }
  EVP_PKEY *key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed->ptr, 32);
  uint8_t pub[32];
  size_t n = sizeof pub;
  int ok = key && EVP_PKEY_get_raw_public_key(key, pub, &n);
  EVP_PKEY_free(key);
  if (!ok) {
    return MS_STATUS_INVALID_INPUT;
  }
  *(out) = ms_bytes_from_span(ms_span_of(pub, n));
  return MS_STATUS_OK;
}

uint8_t msstd_crypto_verify(const MsBytes *key, const MsBytes *data, const MsBytes *signature) {
  if (key->len != 32 || signature->len != 64) {
    return 0;
  }
  EVP_PKEY *pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL, key->ptr, 32);
  EVP_MD_CTX *ctx = pkey ? EVP_MD_CTX_new() : NULL;
  int ok = ctx && EVP_DigestVerifyInit(ctx, NULL, NULL, NULL, pkey) &&
           EVP_DigestVerify(ctx, signature->ptr, 64, bytes_of(data), data->len) == 1;
  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(pkey);
  return (uint8_t)ok;
}
