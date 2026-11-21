/* The system's trusted roots as PEM text, for the downloader (compiler/include/ms/build_fetch.h). Linux reads the first
 * CA bundle a distribution ships (or the file SSL_CERT_FILE names); macOS adds the certificates the Security
 * framework trusts to its /etc/ssl/cert.pem; Windows exports the ROOT certificate store. The caller owns the text. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/build_fetch.h"

#if defined(_WIN32)
#include <windows.h>
#include <wincrypt.h>
#elif defined(__APPLE__)
#include <Security/Security.h>
#endif

typedef struct Text {
    char *ptr; /* owned */
    size_t len;
    size_t cap;
} Text;

static bool text_append(Text *text, const char *data, size_t length) {
    size_t needed = 0;
    if (!ms_size_add(text->len, length, &needed) || !ms_size_add(needed, 1, &needed)) {
        return false;
    }
    if (needed > text->cap) {
        size_t grown = text->cap == 0 ? 1u << 16 : text->cap;
        while (grown < needed) {
            if (!ms_size_mul(grown, 2, &grown)) {
                return false;
            }
        }
        char *const next = realloc(text->ptr, grown);
        if (next == NULL) {
            return false;
        }
        text->ptr = next;
        text->cap = grown;
    }
    if (text->ptr == NULL) {
        return false;
    }
    memcpy(text->ptr + text->len, data, length);
    text->len += length;
    text->ptr[text->len] = 0;
    return true;
}

/* Appends one DER certificate as a PEM block. */
#if defined(_WIN32) || defined(__APPLE__)
static bool text_append_certificate(Text *text, const uint8_t *der, size_t length) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    bool ok = text_append(text, "-----BEGIN CERTIFICATE-----\n", 28);
    char line[65];
    size_t used = 0;
    for (size_t at = 0; ok && at < length; at += 3) {
        const size_t take = length - at < 3 ? length - at : 3;
        uint32_t group = 0;
        for (size_t i = 0; i < 3; i++) {
            group = group << 8 | (i < take ? der[at + i] : 0u);
        }
        for (size_t i = 0; i < 4; i++) {
            line[used++] = i <= take ? alphabet[(group >> (18 - 6 * i)) & 63u] : '=';
        }
        if (used == 64 || at + 3 >= length) {
            line[used++] = '\n';
            ok = text_append(text, line, used);
            used = 0;
        }
    }
    return ok && text_append(text, "-----END CERTIFICATE-----\n", 26);
}
#endif

/* The contents of a file, or false. */
#if !defined(_WIN32)
static bool read_file(const char *path, Text *text) {
    FILE *const file = fopen(path, "rbe");
    if (file == NULL) {
        return false;
    }
    char chunk[1 << 14];
    bool ok = true;
    size_t got = 0;
    while (ok && (got = fread(chunk, 1, sizeof chunk, file)) > 0) {
        ok = text_append(text, chunk, got);
    }
    ok = ok && ferror(file) == 0;
    (void)fclose(file);
    return ok;
}
#endif

#if defined(_WIN32)
static bool add_system_store(Text *text) {
    HCERTSTORE store = CertOpenSystemStoreA(0, "ROOT");
    if (store == NULL) {
        return false;
    }
    const CERT_CONTEXT *cert = NULL;
    bool ok = true;
    while (ok && (cert = CertEnumCertificatesInStore(store, cert)) != NULL) {
        ok = text_append_certificate(text, cert->pbCertEncoded, cert->cbCertEncoded);
    }
    (void)CertCloseStore(store, 0);
    return ok;
}
#elif defined(__APPLE__)
static bool add_anchors(Text *text) {
    CFArrayRef anchors = NULL;
    if (SecTrustCopyAnchorCertificates(&anchors) != errSecSuccess || anchors == NULL) {
        return false;
    }
    bool ok = true;
    for (CFIndex i = 0; ok && i < CFArrayGetCount(anchors); i++) {
        CFDataRef der = SecCertificateCopyData((SecCertificateRef)CFArrayGetValueAtIndex(anchors, i));
        if (der != NULL) {
            ok = text_append_certificate(text, CFDataGetBytePtr(der), (size_t)CFDataGetLength(der));
            CFRelease(der);
        }
    }
    CFRelease(anchors);
    return ok;
}
#endif

#if !defined(_WIN32)
/* The first bundle that exists; SSL_CERT_FILE wins, as it does for OpenSSL. */
static bool add_bundle(Text *text) {
    static const char *const bundles[] = {"/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/ca-bundle.pem",
                                          "/etc/pki/tls/cacert.pem", "/etc/ssl/cert.pem", "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"};
    const char *const named = getenv("SSL_CERT_FILE"); // NOLINT(concurrency-mt-unsafe): read once, before any thread of ms starts a download
    if (named != NULL && named[0] != 0 && read_file(named, text)) {
        return true;
    }
    for (size_t i = 0; i < MS_COUNT_OF(bundles); i++) {
        Text found = {0};
        if (read_file(bundles[i], &found) && found.len > 0) {
            const bool ok = text_append(text, found.ptr, found.len);
            free(found.ptr);
            return ok;
        }
        free(found.ptr);
    }
    return false;
}
#endif

char *ms_fetch_system_roots(size_t *length) {
    Text text = {0};
#if defined(_WIN32)
    const bool any = add_system_store(&text);
#elif defined(__APPLE__)
    const bool bundle = add_bundle(&text);
    const bool anchors = add_anchors(&text);
    const bool any = bundle || anchors;
#else
    const bool any = add_bundle(&text);
#endif
    if (!any || text.len == 0) {
        free(text.ptr);
        return NULL;
    }
    *length = text.len;
    return text.ptr;
}
