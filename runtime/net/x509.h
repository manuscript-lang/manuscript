/* Certificates on OpenSSL: parsing PEM into the facts a program shows, and verifying a chain against given roots at
 * a given time. Pure functions of their arguments (no sockets, no scheduler, no system roots).
 *
 * The verification is OpenSSL's path builder with the policy of @std/net/tls: the roots are the only trust anchors
 * (any certificate in them anchors a path, self-signed or not), the leaf must be fit for a TLS server, validity is
 * judged at the time given, and the name is matched against the leaf's subject alternative names only (DNS names, or
 * IP addresses when the name is one), never its common name. CA constraints, name constraints and critical extensions
 * are OpenSSL's.
 */
#ifndef MS_NET_X509_H
#define MS_NET_X509_H

#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"

typedef enum MsX509Status {
    MS_X509_OK = 0,
    MS_X509_INVALID = 1,   /* a parameter that cannot be right: an empty name, a negative limit */
    MS_X509_BAD_DATA = 2,  /* text that is not a sequence of PEM certificates, or none where some are needed */
    MS_X509_LIMIT = 3,     /* more certificates than the limit */
    MS_X509_REJECTED = 4,  /* the chain does not verify */
    MS_X509_MEMORY = 5
} MsX509Status;

typedef struct MsX509Info {
    char *subject;       /* owned: distinguished name in the RFC 2253 style, e.g. "CN=example.com,O=Example" */
    char *issuer;        /* owned */
    char **dns_names;    /* owned, `dns_count` owned strings */
    size_t dns_count;
    int64_t not_before;  /* Unix seconds */
    int64_t not_after;
    uint8_t *der;        /* owned */
    size_t der_length;
} MsX509Info;

/* Parses every certificate of `pem` (only certificate blocks and white space allowed). `max` is the most to accept
 * (negative: invalid; use INT64_MAX for none). On success `*items` holds `*count` entries to release with
 * ms_x509_free. */
MS_NODISCARD MsX509Status ms_x509_parse(MsBytes pem, int64_t max, MsX509Info **items, size_t *count);
void ms_x509_free(MsX509Info *items, size_t count);

/* Verifies the chain (leaf first) in `chain_pem` against the certificates of `roots_pem`, for `server_name`, at
 * `now_seconds`. Both texts must hold at least one certificate. */
MS_NODISCARD MsX509Status ms_x509_verify(MsBytes chain_pem, MsBytes roots_pem, MsBytes server_name, int64_t now_seconds);

#endif
