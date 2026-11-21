/* Unit tests for src/runtime/net/x509.c: the certificate facts, the name text, the limits and the verification policy. */
#include <stdio.h>
#include <string.h>

#include "../net/x509.h"
#include "support/x509_certs.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

enum { Y2020 = 1577836800, Y2100 = 4102444800LL };

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

static MsX509Status verify(const char *chain, const char *roots, const char *name, int64_t now) {
    return ms_x509_verify(text(chain), text(roots), text(name), now);
}

static void test_facts(void) {
    MsX509Info *items = NULL;
    size_t count = 0;
    CHECK(ms_x509_parse(text(STDLIB_CERT), INT64_MAX, &items, &count) == MS_X509_OK);
    CHECK(count == 1);
    if (count == 1) {
        CHECK(strcmp(items[0].subject, "CN=stdlib.test") == 0);
        CHECK(strcmp(items[0].issuer, "CN=stdlib.test") == 0);
        CHECK(items[0].dns_count == 1 && strcmp(items[0].dns_names[0], "stdlib.test") == 0);
        CHECK(items[0].not_before == Y2020 && items[0].not_after == Y2100);
        CHECK(items[0].der_length > 100 && items[0].der[0] == 0x30);
    }
    ms_x509_free(items, count);
}

static void test_limits(void) {
    MsX509Info *items = NULL;
    size_t count = 0;
    CHECK(ms_x509_parse(text(STDLIB_CERT), 0, &items, &count) == MS_X509_LIMIT);
    CHECK(ms_x509_parse(text(STDLIB_CERT), -1, &items, &count) == MS_X509_INVALID);
    CHECK(ms_x509_parse(text("junk"), INT64_MAX, &items, &count) == MS_X509_BAD_DATA);
    CHECK(ms_x509_parse(text(STDLIB_KEY), INT64_MAX, &items, &count) == MS_X509_BAD_DATA);
    CHECK(ms_x509_parse(text("  \n"), INT64_MAX, &items, &count) == MS_X509_OK && count == 0);
    ms_x509_free(items, count);
    char two[8192];
    snprintf(two, sizeof two, "%s\n\n%s", STDLIB_CERT, STDLIB_CERT);
    CHECK(ms_x509_parse(text(two), INT64_MAX, &items, &count) == MS_X509_OK && count == 2);
    ms_x509_free(items, count);
    CHECK(ms_x509_parse(text(two), 1, &items, &count) == MS_X509_LIMIT);
}

static void test_names(void) {
    MsX509Info *items = NULL;
    size_t count = 0;
    CHECK(ms_x509_parse(text(DN_NAMES), INT64_MAX, &items, &count) == MS_X509_OK);
    CHECK(count == 2);
    if (count == 2) {
        CHECK(strcmp(items[0].subject,
                     "SERIALNUMBER=77,CN=a\\,b,OU=OU,O=O1+O=O2,POSTALCODE=9,STREET=S,L=\\ L#,ST=CA,C=US,"
                     "1.2.3.4=#130178,0.9.2342.19200300.100.1.25=#13076578616d706c65") == 0);
        CHECK(strcmp(items[1].subject, "CN=\xc3\xbcn\xc3\xaf") == 0);
    }
    ms_x509_free(items, count);
}

static void test_verify(void) {
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "stdlib.test", Y2020 + 10) == MS_X509_OK);
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "127.0.0.1", Y2020 + 10) == MS_X509_OK);
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "other.test", Y2020 + 10) == MS_X509_REJECTED);
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "stdlib.test", Y2020 - 1) == MS_X509_REJECTED);
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "stdlib.test", Y2100 + 1) == MS_X509_REJECTED);
    CHECK(verify(STDLIB_CERT, STDLIB_CERT, "", Y2020) == MS_X509_INVALID);
    CHECK(verify("", STDLIB_CERT, "a", Y2020) == MS_X509_BAD_DATA);
    CHECK(verify(STDLIB_CERT, " ", "a", Y2020) == MS_X509_BAD_DATA);
    /* A different root does not vouch for the chain. */
    const char *end = "-----END CERTIFICATE-----\n";
    const char *first_end = strstr(DN_NAMES, end);
    char other[4096];
    if (first_end != NULL) {
        const size_t length = (size_t)(first_end - DN_NAMES) + strlen(end);
        memcpy(other, DN_NAMES, length);
        other[length] = 0;
        CHECK(verify(STDLIB_CERT, other, "stdlib.test", Y2020 + 10) == MS_X509_REJECTED);
    }
}

int main(void) {
    test_facts();
    test_limits();
    test_names();
    test_verify();
    if (failed == 0) {
        printf("x509_test: ok\n");
    }
    return failed;
}
