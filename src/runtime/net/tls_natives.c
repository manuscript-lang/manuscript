/* The certificate natives of @std/net/tls (ms_rt/net.h): parse PEM into CertificateInfo records and verify a chain,
 * both over src/runtime/net/x509.c. */
#include <string.h>

#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/net.h"
#include "ms_rt/safe.h"
#include "x509.h"

/* CertificateInfo at the layout the compiler gives the record (a Timestamp is two words). */
typedef struct CertificateInfo {
    MsStr subject;
    MsStr issuer;
    MsVec dns_names;
    int64_t not_before_seconds, not_before_nanos;
    int64_t not_after_seconds, not_after_nanos;
    MsVec der;
} CertificateInfo;

static void certificate_drop(const uint8_t *slot) {
    CertificateInfo info;
    memcpy(&info, slot, sizeof info);
    msrt_string_free(&info.subject);
    msrt_string_free(&info.issuer);
    msrt_list_drop(&info.dns_names, &msrt_desc_string);
    msrt_free(info.der.ptr);
}

static void certificate_copy(const uint8_t *source, uint8_t *destination) {
    CertificateInfo info;
    memcpy(&info, source, sizeof info);
    CertificateInfo copy = info;
    msrt_string_clone(&info.subject, &copy.subject);
    msrt_string_clone(&info.issuer, &copy.issuer);
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)info.dns_names.len, &copy.dns_names);
    const MsStr *names = info.dns_names.ptr;
    for (size_t i = 0; i < info.dns_names.len; i++) {
        MsStr name;
        msrt_string_clone(&names[i], &name);
        msrt_list_push(&copy.dns_names, &msrt_desc_string, &name);
    }
    msrt_write_bytes(&copy.der, info.der.ptr, info.der.len);
    memcpy(destination, &copy, sizeof copy);
}

static const MsTypeDesc certificate_desc = {
    .size = sizeof(CertificateInfo),
    .align = _Alignof(CertificateInfo),
    .kind = MS_TYPE_KIND_CUSTOM,
    .drop = certificate_drop,
    .copy = certificate_copy,
};

static uint8_t status_of(MsX509Status status) {
    switch (status) {
    case MS_X509_OK: return STATUS_OK;
    case MS_X509_INVALID: return STATUS_INVALID_INPUT;
    case MS_X509_BAD_DATA: return STATUS_INVALID_DATA;
    case MS_X509_LIMIT: return STATUS_LIMIT_EXCEEDED;
    case MS_X509_REJECTED: return STATUS_AUTHENTICATION_FAILED;
    case MS_X509_MEMORY: break;
    }
    return STATUS_FAILED;
}


static CertificateInfo record_of(const MsX509Info *item) {
    CertificateInfo info = {
        .not_before_seconds = item->not_before,
        .not_after_seconds = item->not_after,
    };
    msrt_string_from_bytes((const uint8_t *)item->subject, strlen(item->subject), &info.subject);
    msrt_string_from_bytes((const uint8_t *)item->issuer, strlen(item->issuer), &info.issuer);
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)item->dns_count, &info.dns_names);
    for (size_t i = 0; i < item->dns_count; i++) {
        MsStr name;
        msrt_string_from_bytes((const uint8_t *)item->dns_names[i], strlen(item->dns_names[i]), &name);
        msrt_list_push(&info.dns_names, &msrt_desc_string, &name);
    }
    msrt_write_bytes(&info.der, item->der, item->der_length);
    return info;
}

uint8_t msstd_tls_parse_certificates(const MsStr *pem, uint8_t has_max, int64_t max, MsVec *out) {
    MsX509Info *items = NULL;
    size_t count = 0;
    const MsX509Status status = ms_x509_parse(msrt_str_bytes(pem), has_max != 0 ? max : INT64_MAX, &items, &count);
    if (status != MS_X509_OK) {
        return status_of(status);
    }
    msrt_list_with_capacity(&certificate_desc, (int64_t)count, out);
    for (size_t i = 0; i < count; i++) {
        const CertificateInfo info = record_of(&items[i]);
        msrt_list_push(out, &certificate_desc, &info);
    }
    ms_x509_free(items, count);
    return STATUS_OK;
}

uint8_t msstd_tls_verify_certificates(const MsStr *chain, const MsStr *roots, const MsStr *server_name, const MsTlsTimestamp *now) {
    return status_of(ms_x509_verify(msrt_str_bytes(chain), msrt_str_bytes(roots), msrt_str_bytes(server_name), now->seconds));
}
