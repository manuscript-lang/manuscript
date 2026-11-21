/* Certificates on OpenSSL (x509.h). */
#include "x509.h"

#include <openssl/asn1.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/chars.h"

static const char begin_mark[] = "-----BEGIN CERTIFICATE-----";
static const char end_mark[] = "-----END CERTIFICATE-----";

/* ---- PEM blocks ---- */

/* The next certificate block of `rest` (white space skipped before it). MS_X509_OK with an empty `*block` at the end of
 * the text; MS_X509_BAD_DATA for anything that is not a complete certificate block. */
static MsX509Status next_block(MsBytes *rest, MsBytes *block) {
    while (rest->len > 0 && ms_ascii_is_space(rest->ptr[0])) {
        rest->ptr++;
        rest->len--;
    }
    *block = ms_bytes_of(rest->ptr, 0);
    if (rest->len == 0) {
        return MS_X509_OK;
    }
    if (!ms_bytes_starts_with(*rest, ms_bytes_of((const uint8_t *)begin_mark, sizeof begin_mark - 1))) {
        return MS_X509_BAD_DATA;
    }
    size_t at = 0;
    if (!ms_bytes_find(*rest, ms_bytes_of((const uint8_t *)end_mark, sizeof end_mark - 1), &at)) {
        return MS_X509_BAD_DATA;
    }
    const size_t length = at + sizeof end_mark - 1;
    *block = ms_bytes_of(rest->ptr, length);
    rest->ptr += length;
    rest->len -= length;
    return MS_X509_OK;
}

static X509 *read_block(MsBytes block) {
    if (block.len > INT32_MAX) {
        return NULL;
    }
    BIO *bio = BIO_new_mem_buf(block.ptr, (int)block.len);
    if (bio == NULL) {
        return NULL;
    }
    X509 *certificate = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    return certificate;
}

/* Every certificate of the text, at most `max`. */
static MsX509Status read_all(MsBytes pem, int64_t max, STACK_OF(X509) **out) {
    STACK_OF(X509) *found = sk_X509_new_null();
    if (found == NULL) {
        return MS_X509_MEMORY;
    }
    MsX509Status status = MS_X509_OK;
    MsBytes rest = pem;
    for (;;) {
        MsBytes block;
        status = next_block(&rest, &block);
        if (status != MS_X509_OK || block.len == 0) {
            break;
        }
        X509 *certificate = read_block(block);
        if (certificate == NULL) {
            status = MS_X509_BAD_DATA;
            break;
        }
        if ((int64_t)sk_X509_num(found) >= max) {
            X509_free(certificate);
            status = MS_X509_LIMIT;
            break;
        }
        if (sk_X509_push(found, certificate) == 0) {
            X509_free(certificate);
            status = MS_X509_MEMORY;
            break;
        }
    }
    if (status != MS_X509_OK) {
        sk_X509_pop_free(found, X509_free);
        return status;
    }
    *out = found;
    return MS_X509_OK;
}

/* ---- distinguished names ---- */

typedef struct Text {
    char *data;
    size_t length, capacity;
    bool failed;
} Text;

static void text_put(Text *text, const char *bytes, size_t count) {
    size_t need = 0;
    if (text->failed || !ms_size_add(text->length, count, &need) || !ms_size_add(need, 1, &need)) {
        text->failed = true;
        return;
    }
    if (need > text->capacity) {
        size_t capacity = text->capacity == 0 ? 64 : text->capacity;
        while (capacity < need) {
            if (!ms_size_mul(capacity, 2, &capacity)) {
                text->failed = true;
                return;
            }
        }
        char *grown = realloc(text->data, capacity);
        if (grown == NULL) {
            text->failed = true;
            return;
        }
        text->data = grown;
        text->capacity = capacity;
    }
    if (text->data == NULL) {
        text->failed = true;
        return;
    }
    memcpy(text->data + text->length, bytes, count);
    text->length += count;
    text->data[text->length] = 0;
}

static void text_char(Text *text, char byte) { text_put(text, &byte, 1); }
static void text_string(Text *text, const char *string) { text_put(text, string, strlen(string)); }

static char *copy_text(const char *text, size_t length) {
    char *copy = malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, text, length);
        copy[length] = 0;
    }
    return copy;
}

/* A value with the RFC 2253 specials, a leading `#` or space and a trailing space escaped. */
static void put_escaped(Text *text, const char *value) {
    const size_t length = strlen(value);
    for (size_t i = 0; i < length; i++) {
        const char c = value[i];
        const bool special = c == ',' || c == '+' || c == '"' || c == '\\' || c == '<' || c == '>' || c == ';';
        const bool edge = (c == ' ' && (i == 0 || i + 1 == length)) || (c == '#' && i == 0);
        if (special || edge) {
            text_char(text, '\\');
        }
        text_char(text, c);
    }
}

static bool is_printable(char c) {
    return ms_ascii_is_digit((uint8_t)c) || ms_ascii_is_alpha((uint8_t)c) || (c != 0 && strchr(" '()+,-./:=?", c) != NULL);
}

/* `#` and the hex of the value as a DER string: PrintableString when it can be, else UTF8String. */
static void put_der_hex(Text *text, const char *value) {
    const size_t length = strlen(value);
    bool printable = true;
    for (size_t i = 0; i < length; i++) {
        printable = printable && is_printable(value[i]);
    }
    uint8_t head[12];
    size_t used = 0;
    head[used++] = printable ? 0x13 : 0x0c;
    if (length < 128) {
        head[used++] = (uint8_t)length;
    } else {
        uint8_t digits[8];
        size_t count = 0;
        for (size_t rest = length; rest > 0; rest >>= 8) {
            digits[count++] = (uint8_t)(rest & 0xff);
        }
        head[used++] = (uint8_t)(0x80 | count);
        while (count > 0) {
            head[used++] = digits[--count];
        }
    }
    static const char hex[] = "0123456789abcdef";
    text_char(text, '#');
    for (size_t i = 0; i < used; i++) {
        text_char(text, hex[head[i] >> 4]);
        text_char(text, hex[head[i] & 15]);
    }
    for (size_t i = 0; i < length; i++) {
        text_char(text, hex[(uint8_t)value[i] >> 4]);
        text_char(text, hex[(uint8_t)value[i] & 15]);
    }
}

enum { GROUP_COUNTRY, GROUP_PROVINCE, GROUP_LOCALITY, GROUP_STREET, GROUP_POSTAL, GROUP_ORGANIZATION, GROUP_UNIT, GROUPS };

static const char *const group_labels[GROUPS] = {"C", "ST", "L", "STREET", "POSTALCODE", "O", "OU"};

typedef struct Attribute {
    char *value;   /* owned UTF-8 */
    char *oid;     /* owned, dotted; NULL for a standard attribute */
    int group;     /* GROUP_* for a standard attribute that can repeat; -1 otherwise */
} Attribute;

static int group_of(int nid) {
    switch (nid) {
    case NID_countryName: return GROUP_COUNTRY;
    case NID_stateOrProvinceName: return GROUP_PROVINCE;
    case NID_localityName: return GROUP_LOCALITY;
    case NID_streetAddress: return GROUP_STREET;
    case NID_postalCode: return GROUP_POSTAL;
    case NID_organizationName: return GROUP_ORGANIZATION;
    case NID_organizationalUnitName: return GROUP_UNIT;
    default: return -1;
    }
}

/* The attribute's value as UTF-8, or NULL for a value that is not a string. */
static char *value_text(const X509_NAME_ENTRY *entry) {
    const ASN1_STRING *value = X509_NAME_ENTRY_get_data(entry);
    unsigned char *utf8 = NULL;
    if (ASN1_STRING_to_UTF8(&utf8, value) < 0) {
        return NULL;
    }
    char *copy = copy_text((const char *)utf8, strlen((const char *)utf8));
    OPENSSL_free(utf8);
    return copy;
}

static void attributes_free(Attribute *attributes, int count) {
    for (int i = 0; i < count; i++) {
        free(attributes[i].value);
        free(attributes[i].oid);
    }
    free(attributes);
}

/* The name as text: other attributes in certificate order, then country, province, locality, street, postal code,
 * organization, unit, common name and serial number, the whole sequence printed last to first with `+` between the
 * values of one group. Values the certificate repeats keep all (common name and serial number: the last). */
static void put_name(Text *text, const X509_NAME *name) {
    const int count = X509_NAME_entry_count(name);
    Attribute *attributes = calloc((size_t)(count > 0 ? count : 1), sizeof *attributes);
    if (attributes == NULL) {
        text->failed = true;
        return;
    }
    int used = 0, common = -1, serial = -1;
    for (int i = 0; i < count; i++) {
        const X509_NAME_ENTRY *entry = X509_NAME_get_entry(name, i);
        char *value = value_text(entry);
        if (value == NULL) {
            continue;
        }
        const ASN1_OBJECT *object = X509_NAME_ENTRY_get_object(entry);
        const int nid = OBJ_obj2nid(object);
        Attribute *slot = &attributes[used];
        slot->value = value;
        slot->group = group_of(nid);
        if (nid == NID_commonName) {
            common = used;
        } else if (nid == NID_serialNumber) {
            serial = used;
        } else if (slot->group < 0) {
            char oid[128];
            OBJ_obj2txt(oid, sizeof oid, object, 1);
            slot->oid = copy_text(oid, strlen(oid));
        }
        used++;
    }
    /* The RDNs in print order: the sequence reversed. */
    bool first = true;
    if (serial >= 0) {
        text_string(text, "SERIALNUMBER=");
        put_escaped(text, attributes[serial].value);
        first = false;
    }
    if (common >= 0) {
        text_string(text, first ? "CN=" : ",CN=");
        put_escaped(text, attributes[common].value);
        first = false;
    }
    for (int group = GROUPS - 1; group >= 0; group--) {
        bool inside = false;
        for (int i = 0; i < used; i++) {
            if (attributes[i].group != group) {
                continue;
            }
            if (inside) {
                text_char(text, '+');
            } else if (!first) {
                text_char(text, ',');
            }
            inside = true;
            first = false;
            text_string(text, group_labels[group]);
            text_char(text, '=');
            put_escaped(text, attributes[i].value);
        }
    }
    for (int i = used - 1; i >= 0; i--) {
        if (attributes[i].oid == NULL) {
            continue;
        }
        if (!first) {
            text_char(text, ',');
        }
        first = false;
        text_string(text, attributes[i].oid);
        text_char(text, '=');
        put_der_hex(text, attributes[i].value);
    }
    attributes_free(attributes, count > 0 ? count : 1);
}

static char *name_text(const X509_NAME *name) {
    Text text = {0};
    text_put(&text, "", 0);
    put_name(&text, name);
    if (text.failed) {
        free(text.data);
        return NULL;
    }
    return text.data;
}

/* ---- facts ---- */

static bool seconds_of(const ASN1_TIME *time, int64_t *out) {
    ASN1_TIME *epoch = ASN1_TIME_set(NULL, 0);
    int days = 0, seconds = 0;
    const bool ok = epoch != NULL && ASN1_TIME_diff(&days, &seconds, epoch, time) == 1;
    ASN1_TIME_free(epoch);
    if (ok) {
        *out = (int64_t)days * 86400 + seconds;
    }
    return ok;
}

static bool dns_names_of(X509 *certificate, MsX509Info *info) {
    GENERAL_NAMES *names = X509_get_ext_d2i(certificate, NID_subject_alt_name, NULL, NULL);
    if (names == NULL) {
        return true;
    }
    const int total = sk_GENERAL_NAME_num(names);
    info->dns_names = calloc((size_t)(total > 0 ? total : 1), sizeof *info->dns_names);
    bool ok = info->dns_names != NULL;
    for (int i = 0; ok && i < total; i++) {
        const GENERAL_NAME *name = sk_GENERAL_NAME_value(names, i);
        if (name->type != GEN_DNS) {
            continue;
        }
        const size_t length = (size_t)ASN1_STRING_length(name->d.dNSName);
        char *copy = malloc(length + 1);
        ok = copy != NULL;
        if (ok) {
            memcpy(copy, ASN1_STRING_get0_data(name->d.dNSName), length);
            copy[length] = 0;
            info->dns_names[info->dns_count++] = copy;
        }
    }
    GENERAL_NAMES_free(names);
    return ok;
}

static bool info_of(X509 *certificate, MsX509Info *info) {
    info->subject = name_text(X509_get_subject_name(certificate));
    info->issuer = name_text(X509_get_issuer_name(certificate));
    bool ok = info->subject != NULL && info->issuer != NULL;
    ok = ok && seconds_of(X509_get0_notBefore(certificate), &info->not_before);
    ok = ok && seconds_of(X509_get0_notAfter(certificate), &info->not_after);
    ok = ok && dns_names_of(certificate, info);
    if (ok) {
        unsigned char *der = NULL;
        const int length = i2d_X509(certificate, &der);
        ok = length > 0;
        if (ok) {
            info->der = malloc((size_t)length);
            ok = info->der != NULL;
            if (ok) {
                memcpy(info->der, der, (size_t)length);
                info->der_length = (size_t)length;
            }
        }
        OPENSSL_free(der);
    }
    return ok;
}

void ms_x509_free(MsX509Info *items, size_t count) {
    for (size_t i = 0; items != NULL && i < count; i++) {
        free(items[i].subject);
        free(items[i].issuer);
        for (size_t n = 0; n < items[i].dns_count; n++) {
            free(items[i].dns_names[n]);
        }
        free(items[i].dns_names);
        free(items[i].der);
    }
    free(items);
}

MsX509Status ms_x509_parse(MsBytes pem, int64_t max, MsX509Info **items, size_t *count) {
    if (max < 0) {
        return MS_X509_INVALID;
    }
    STACK_OF(X509) *found = NULL;
    const MsX509Status read = read_all(pem, max, &found);
    if (read != MS_X509_OK) {
        return read;
    }
    const size_t total = (size_t)sk_X509_num(found);
    MsX509Info *list = calloc(total > 0 ? total : 1, sizeof *list);
    MsX509Status status = list == NULL ? MS_X509_MEMORY : MS_X509_OK;
    for (size_t i = 0; status == MS_X509_OK && i < total; i++) {
        if (!info_of(sk_X509_value(found, (int)i), &list[i])) {
            status = MS_X509_BAD_DATA;
            ms_x509_free(list, i + 1);
            list = NULL;
        }
    }
    sk_X509_pop_free(found, X509_free);
    if (status == MS_X509_OK) {
        *items = list;
        *count = total;
    } else {
        free(list);
    }
    return status;
}

/* ---- verification ---- */

/* The host name without the brackets of an IPv6 literal or the trailing dot of a name, as a C string. */
static char *host_text(MsBytes name, bool *is_ip) {
    MsBytes host = name;
    if (host.len >= 2 && host.ptr[0] == '[' && host.ptr[host.len - 1] == ']') {
        host = ms_bytes_of(host.ptr + 1, host.len - 2);
    }
    char *copy = malloc(host.len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, host.ptr, host.len);
    copy[host.len] = 0;
    ASN1_OCTET_STRING *address = a2i_IPADDRESS(copy);
    *is_ip = address != NULL;
    ASN1_OCTET_STRING_free(address);
    size_t length = host.len;
    while (!*is_ip && length > 0 && copy[length - 1] == '.') {
        copy[--length] = 0;
    }
    return copy;
}

static bool set_name(X509_VERIFY_PARAM *param, MsBytes name) {
    bool is_ip = false;
    char *host = host_text(name, &is_ip);
    if (host == NULL) {
        return false;
    }
    X509_VERIFY_PARAM_set_hostflags(param, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT);
    const int ok = is_ip ? X509_VERIFY_PARAM_set1_ip_asc(param, host) : X509_VERIFY_PARAM_set1_host(param, host, 0);
    free(host);
    return ok == 1;
}

static MsX509Status verify_chain(STACK_OF(X509) *chain, STACK_OF(X509) *roots, MsBytes name, int64_t now) {
    X509_STORE *store = X509_STORE_new();
    X509_STORE_CTX *context = X509_STORE_CTX_new();
    STACK_OF(X509) *untrusted = sk_X509_new_null();
    MsX509Status status = MS_X509_MEMORY;
    if (store != NULL && context != NULL && untrusted != NULL) {
        bool loaded = true;
        for (int i = 0; loaded && i < sk_X509_num(roots); i++) {
            loaded = X509_STORE_add_cert(store, sk_X509_value(roots, i)) == 1;
        }
        for (int i = 1; loaded && i < sk_X509_num(chain); i++) {
            loaded = sk_X509_push(untrusted, sk_X509_value(chain, i)) > 0;
        }
        if (loaded && X509_STORE_CTX_init(context, store, sk_X509_value(chain, 0), untrusted) == 1 &&
            X509_STORE_CTX_set_default(context, "ssl_server") == 1) {
            X509_VERIFY_PARAM *param = X509_STORE_CTX_get0_param(context);
            X509_VERIFY_PARAM_set_time(param, (time_t)now);
            X509_VERIFY_PARAM_set_auth_level(param, 0);
            X509_VERIFY_PARAM_set_flags(param, X509_V_FLAG_PARTIAL_CHAIN);
            status = set_name(param, name) && X509_verify_cert(context) == 1 ? MS_X509_OK : MS_X509_REJECTED;
        }
    }
    sk_X509_free(untrusted); /* its members belong to `chain` */
    X509_STORE_CTX_free(context);
    X509_STORE_free(store);
    ERR_clear_error();
    return status;
}

MsX509Status ms_x509_verify(MsBytes chain_pem, MsBytes roots_pem, MsBytes server_name, int64_t now_seconds) {
    if (server_name.len == 0) {
        return MS_X509_INVALID;
    }
    STACK_OF(X509) *chain = NULL;
    STACK_OF(X509) *roots = NULL;
    MsX509Status status = read_all(chain_pem, INT64_MAX, &chain);
    if (status == MS_X509_OK && sk_X509_num(chain) == 0) {
        status = MS_X509_BAD_DATA;
    }
    if (status == MS_X509_OK) {
        status = read_all(roots_pem, INT64_MAX, &roots);
    }
    if (status == MS_X509_OK && sk_X509_num(roots) == 0) {
        status = MS_X509_BAD_DATA;
    }
    if (status == MS_X509_OK) {
        status = verify_chain(chain, roots, server_name, now_seconds);
    }
    sk_X509_pop_free(chain, X509_free);
    sk_X509_pop_free(roots, X509_free);
    return status;
}
