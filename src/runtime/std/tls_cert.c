/* runtime/std/tls_cert.c: X.509 certificates for @std/net/tls: parsing, and verifying a chain for a server
 * name at a given time. */
#include <openssl/x509v3.h>

#include "base/alloc.h"
#include "runtime/std/tls.h"

/* A parsed DER certificate; NULL when it is malformed. */
static X509 *ms_tls_x509_parse(MsSpan der) {
  const unsigned char *at = der.ptr;
  X509 *cert = d2i_X509(NULL, &at, (long)der.len);
  if (cert != NULL && (size_t)(at - der.ptr) != der.len) {
    X509_free(cert);
    return NULL;
  }
  return cert;
}

/* The time as seconds since the Unix epoch; false when it is not a valid time. */
static bool ms_tls_time_seconds(const ASN1_TIME *time, int64_t *seconds) {
  ASN1_TIME *epoch = ASN1_TIME_set(NULL, 0);
  int days = 0;
  int secs = 0;
  const bool ok = epoch != NULL && ASN1_TIME_diff(&days, &secs, epoch, time) == 1;
  ASN1_TIME_free(epoch);
  if (ok) {
    *seconds = (int64_t)days * 86400 + secs;
  }
  return ok;
}

/* ---- parse_certificates ---- */

/* `CertificateInfo` at its natural layout. */
typedef struct MsCertificateInfo {
  MsString subject;
  MsString issuer;
  MsList dns_names; /* MsString */
  MsTimestamp not_before;
  MsTimestamp not_after;
  MsBytes der;
} MsCertificateInfo;

static void dns_names_of(X509 *cert, MsList *out) {
  GENERAL_NAMES *names = X509_get_ext_d2i(cert, NID_subject_alt_name, NULL, NULL);
  for (int i = 0; names != NULL && i < sk_GENERAL_NAME_num(names); i++) {
    const GENERAL_NAME *name = sk_GENERAL_NAME_value(names, i);
    if (name->type != GEN_DNS) {
      continue;
    }
    const MsString text = ms_string_from_span(
        ms_span_of(ASN1_STRING_get0_data(name->d.dNSName), (size_t)ASN1_STRING_length(name->d.dNSName)));
    ms_list_push(out, sizeof text, &text);
  }
  GENERAL_NAMES_free(names);
}

static bool describe(MsSpan der, MsCertificateInfo *info) {
  X509 *cert = ms_tls_x509_parse(der);
  if (cert == NULL) {
    return false;
  }
  int64_t from = 0;
  int64_t to = 0;
  const bool ok = ms_tls_time_seconds(X509_get0_notBefore(cert), &from) &&
                  ms_tls_time_seconds(X509_get0_notAfter(cert), &to);
  if (ok) {
    *info = (MsCertificateInfo){.subject = ms_tls_dn_text(X509_get_subject_name(cert)),
                                .issuer = ms_tls_dn_text(X509_get_issuer_name(cert)),
                                .not_before = {from, 0},
                                .not_after = {to, 0},
                                .der = ms_bytes_from_span(der)};
    dns_names_of(cert, &info->dns_names);
  }
  X509_free(cert);
  return ok;
}

static void info_free(MsCertificateInfo *info) {
  ms_string_release(&info->subject);
  ms_string_release(&info->issuer);
  ms_bytes_list_free(&info->dns_names);
  ms_bytes_free(&info->der);
}

uint8_t msstd_tls_parse_certificates(const MsString *pem, uint8_t has_max, int64_t max, MsList *out) {
  *out = (MsList){0};
  if (has_max != 0 && max < 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsList ders = {0};
  uint8_t status = ms_tls_pem_certificates(ms_string_span(pem), has_max != 0 ? max : -1, &ders);
  const MsBytes *items = (const MsBytes *)(const void *)ders.ptr;
  for (size_t i = 0; status == MS_STATUS_OK && i < ders.len; i++) {
    MsCertificateInfo info;
    if (!describe(ms_bytes_span(&items[i]), &info)) {
      status = MS_STATUS_INVALID_DATA;
      break;
    }
    ms_list_push(out, sizeof info, &info);
  }
  ms_bytes_list_free(&ders);
  if (status != MS_STATUS_OK) {
    MsCertificateInfo *done = (MsCertificateInfo *)(void *)out->ptr;
    for (size_t i = 0; i < out->len; i++) {
      info_free(&done[i]);
    }
    ms_list_free(out);
  }
  return status;
}

/* ---- verify_certificates ---- */

static X509 *parse_one(const MsBytes *der) {
  return ms_tls_x509_parse(ms_bytes_span(der));
}

/* The certificates of `ders` in a stack (the first is returned in `*first` when asked), or NULL when one is
 * malformed. */
static STACK_OF(X509) * stack_of(const MsList *ders, X509 **first) {
  STACK_OF(X509) *stack = sk_X509_new_null();
  const MsBytes *items = (const MsBytes *)(const void *)ders->ptr;
  for (size_t i = 0; i < ders->len; i++) {
    X509 *cert = parse_one(&items[i]);
    if (cert == NULL) {
      sk_X509_pop_free(stack, X509_free);
      return NULL;
    }
    (void)sk_X509_push(stack, cert);
  }
  if (first != NULL && sk_X509_num(stack) > 0) {
    *first = sk_X509_value(stack, 0);
  }
  return stack;
}

/* Trusts the system store when no roots were given. */
static void trust_system(X509_STORE *store) {
#ifdef _WIN32
  (void)X509_STORE_load_store(store, "org.openssl.winstore://");
#else
  (void)X509_STORE_set_default_paths(store);
#endif
}

static bool name_is_ip(const char *text) {
  ASN1_OCTET_STRING *address = a2i_IPADDRESS(text);
  const bool ip = address != NULL;
  ASN1_OCTET_STRING_free(address);
  return ip;
}

static bool set_name(X509_VERIFY_PARAM *param, MsSpan name) {
  if (name.len >= 2 && name.ptr[0] == '[' && name.ptr[name.len - 1] == ']') {
    name = ms_span_of(name.ptr + 1, name.len - 2);
  }
  char *text = ms_alloc(name.len + 1);
  if (name.len > 0) {
    __builtin_memcpy(text, name.ptr, name.len);
  }
  text[name.len] = '\0';
  bool ok = false;
  if (name_is_ip(text)) {
    ok = X509_VERIFY_PARAM_set1_ip_asc(param, text) == 1;
  } else {
    X509_VERIFY_PARAM_set_hostflags(param, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT);
    ok = X509_VERIFY_PARAM_set1_host(param, text, name.len) == 1;
  }
  ms_free(text);
  return ok;
}

/* Verifies the leaf `chain[0]` (with the rest as intermediates) for a server called `name` at `now` (Unix
 * seconds) against `roots`: OK or AUTHENTICATION_FAILED. */
static uint8_t ms_tls_verify(const MsList *chain, const MsList *roots, MsSpan name, int64_t now) {
  X509 *leaf = NULL;
  STACK_OF(X509) *untrusted = stack_of(chain, &leaf);
  X509_STORE *store = X509_STORE_new();
  X509_STORE_CTX *ctx = X509_STORE_CTX_new();
  uint8_t status = MS_STATUS_AUTHENTICATION_FAILED;
  const MsBytes *anchors = (const MsBytes *)(const void *)roots->ptr;
  bool loaded = untrusted != NULL && leaf != NULL && store != NULL && ctx != NULL;
  for (size_t i = 0; loaded && i < roots->len; i++) {
    X509 *anchor = parse_one(&anchors[i]);
    loaded = anchor != NULL && X509_STORE_add_cert(store, anchor) == 1;
    X509_free(anchor);
  }
  if (loaded && roots->len == 0) {
    trust_system(store);
  }
  if (loaded && X509_STORE_CTX_init(ctx, store, leaf, untrusted) == 1) {
    X509_VERIFY_PARAM *param = X509_STORE_CTX_get0_param(ctx);
    X509_VERIFY_PARAM_set_time(param, (time_t)now);
    (void)X509_VERIFY_PARAM_set_purpose(param, X509_PURPOSE_SSL_SERVER);
    if (set_name(param, name) && X509_verify_cert(ctx) == 1) {
      status = MS_STATUS_OK;
    }
  }
  X509_STORE_CTX_free(ctx);
  X509_STORE_free(store);
  sk_X509_pop_free(untrusted, X509_free);
  return status;
}

uint8_t msstd_tls_verify_certificates(const MsString *chain_pem, const MsString *roots_pem,
                                      const MsString *server_name, const MsTimestamp *now) {
  if (ms_string_span(server_name).len == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsList chain = {0};
  MsList roots = {0};
  uint8_t status = ms_tls_pem_certificates(ms_string_span(chain_pem), -1, &chain);
  if (status == MS_STATUS_OK && chain.len == 0) {
    status = MS_STATUS_INVALID_DATA;
  }
  if (status == MS_STATUS_OK) {
    status = ms_tls_pem_certificates(ms_string_span(roots_pem), -1, &roots);
  }
  if (status == MS_STATUS_OK) {
    status = ms_tls_verify(&chain, &roots, ms_string_span(server_name), now->seconds);
  }
  ms_bytes_list_free(&chain);
  ms_bytes_list_free(&roots);
  return status;
}

static MsString message_of(uint8_t status) {
  switch (status) {
  case MS_STATUS_INVALID_INPUT:
    return ms_string_from_span(ms_span_of_text("TLS: invalid input"));
  case MS_STATUS_INVALID_DATA:
    return ms_string_from_span(ms_span_of_text("TLS: invalid data"));
  case MS_STATUS_LIMIT_EXCEEDED:
    return ms_string_from_span(ms_span_of_text("TLS: limit exceeded"));
  default:
    return ms_string_from_span(ms_span_of_text("TLS: authentication failed"));
  }
}

void msstd_tls_error_message(uint8_t status, MsString *out) {
  *out = message_of(status);
}
