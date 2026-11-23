/* runtime/std/tls.h: PEM text and X.509 certificates (tls_pem.c, tls_cert.c, tls_dn.c) for @std/net/tls. */
#ifndef MS_RUNTIME_STD_TLS_H
#define MS_RUNTIME_STD_TLS_H

#include <openssl/x509.h>

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"
#include "runtime/std/http_headers.h"
#include "runtime/std/time.h"

/* ---- PEM (tls_pem.c) ---- */

/* Text made only of CERTIFICATE blocks (no headers) separated by whitespace, as a list of MsBytes (DER).
 * INVALID_DATA for anything else; LIMIT_EXCEEDED once more than `max` blocks (negative: no limit). */
uint8_t ms_tls_pem_certificates(MsSpan text, int64_t max, MsList *ders);

/* ---- distinguished names (tls_dn.c) ---- */

/* The RFC 2253 style text of a name: standard attributes in the order C, ST, L, STREET, POSTALCODE, O, OU,
 * CN, SERIALNUMBER (others first), printed from last to first; values escaped. */
MsString ms_tls_dn_text(const X509_NAME *name);

/* ---- certificates (tls_cert.c) ---- */

/* A parsed DER certificate; NULL when it is malformed. */
X509 *ms_tls_x509_parse(MsSpan der);
/* The time as seconds since the Unix epoch; false when it is not a valid time. */
bool ms_tls_time_seconds(const ASN1_TIME *time, int64_t *seconds);

/* Verifies the leaf `chain[0]` (with the rest as intermediates) for a server called `name` at `now` (Unix
 * seconds) against `roots`: OK or AUTHENTICATION_FAILED. */
uint8_t ms_tls_verify(const MsList *chain, const MsList *roots, MsSpan name, int64_t now);

/* ---- natives (tls_cert.c) ---- */

/* A parsed certificate in the layout of `CertificateInfo`. */
/* ms-sig: msstd_tls_parse_certificates(pem: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal) -> u8
 * @domain=TLS */
uint8_t msstd_tls_parse_certificates(const MsString *pem, uint8_t has_max, int64_t max, MsList *out);
/* ms-sig: msstd_tls_verify_certificates(chain: *const StrVal, roots: *const StrVal, server_name: *const
 * StrVal, now: *const Timestamp) -> u8 @domain=TLS */
uint8_t msstd_tls_verify_certificates(const MsString *chain_pem, const MsString *roots_pem,
                                      const MsString *server_name, const MsTimestamp *now);
/* ms-sig: msstd_tls_error_message(status: u8, out: *mut StrVal) @domain=TLS @end */
void msstd_tls_error_message(uint8_t status, MsString *out);

#endif
