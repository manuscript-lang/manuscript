/* runtime/std/tls_dn.c: distinguished-name text in the RFC 2253 style of certificate subjects. */
#include <openssl/asn1.h>
#include <openssl/objects.h>

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/std/tls.h"

enum { GROUP_C, GROUP_ST, GROUP_L, GROUP_STREET, GROUP_POSTAL, GROUP_O, GROUP_OU, GROUPS };

static const char *const group_labels[GROUPS] = {"C", "ST", "L", "STREET", "POSTALCODE", "O", "OU"};
static const char *const group_oids[GROUPS] = {"2.5.4.6",  "2.5.4.8",  "2.5.4.7", "2.5.4.9",
                                               "2.5.4.17", "2.5.4.10", "2.5.4.11"};

typedef struct Extra {
  MsString oid;
  MsString value;
} Extra;

typedef struct Fields {
  MsList groups[GROUPS]; /* MsString */
  MsString common;
  MsString serial;
  bool has_common;
  bool has_serial;
  MsList extra; /* Extra */
} Fields;

static void put(MsList *list, MsString value) {
  ms_list_push(list, sizeof value, &value);
}

static void fields_add(Fields *fields, MsString oid, MsString value) {
  const MsSpan id = ms_string_span(&oid);
  for (int g = 0; g < GROUPS; g++) {
    if (ms_span_is_text(id, group_oids[g])) {
      put(&fields->groups[g], value);
      ms_string_release(&oid);
      return;
    }
  }
  if (ms_span_is_text(id, "2.5.4.3") || ms_span_is_text(id, "2.5.4.5")) {
    const bool common = ms_span_is_text(id, "2.5.4.3");
    MsString *slot = common ? &fields->common : &fields->serial;
    bool *has = common ? &fields->has_common : &fields->has_serial;
    if (*has) {
      ms_string_release(slot);
    }
    *slot = value;
    *has = true;
    ms_string_release(&oid);
    return;
  }
  const Extra extra = {oid, value};
  ms_list_push(&fields->extra, sizeof extra, &extra);
}

static void fields_free(Fields *fields) {
  for (int g = 0; g < GROUPS; g++) {
    ms_bytes_list_free(&fields->groups[g]);
  }
  ms_string_release(&fields->common);
  ms_string_release(&fields->serial);
  const Extra *extra = (const Extra *)(const void *)fields->extra.ptr;
  for (size_t i = 0; i < fields->extra.len; i++) {
    MsString oid = extra[i].oid;
    MsString value = extra[i].value;
    ms_string_release(&oid);
    ms_string_release(&value);
  }
  ms_list_free(&fields->extra);
}

static bool needs_escape(uint8_t c) {
  return c == ',' || c == '+' || c == '"' || c == '\\' || c == '<' || c == '>' || c == ';';
}

static void escape(MsStrBuild *out, MsSpan value) {
  for (size_t i = 0; i < value.len; i++) {
    const uint8_t c = value.ptr[i];
    const bool edge = (c == ' ' && (i == 0 || i + 1 == value.len)) || (c == '#' && i == 0);
    if (needs_escape(c) || edge) {
      ms_strbuild_append_byte(out, '\\');
    }
    ms_strbuild_append_byte(out, c);
  }
}

static bool printable(uint8_t c) {
  const bool alnum = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
  return alnum || (c != 0 && __builtin_memchr(" '()+,-./:=?", c, 12) != NULL);
}

/* An attribute of an unknown type: `OID=#` and the hex of its value as a DER string. */
static void unknown_attribute(MsStrBuild *out, const Extra *extra) {
  const MsSpan value = ms_string_span(&extra->value);
  bool plain = true;
  for (size_t i = 0; i < value.len; i++) {
    plain = plain && printable(value.ptr[i]);
  }
  uint8_t header[10];
  size_t used = 0;
  header[used++] = plain ? 0x13 : 0x0c;
  if (value.len < 128) {
    header[used++] = (uint8_t)value.len;
  } else {
    uint8_t digits[8];
    size_t count = 0;
    for (size_t n = value.len; n > 0; n >>= 8) {
      digits[count++] = (uint8_t)(n & 0xff);
    }
    header[used++] = (uint8_t)(0x80 | count);
    while (count > 0) {
      header[used++] = digits[--count];
    }
  }
  ms_strbuild_append(out, ms_string_span(&extra->oid));
  ms_strbuild_append_text(out, "=#");
  for (size_t i = 0; i < used + value.len; i++) {
    const uint8_t b = i < used ? header[i] : value.ptr[i - used];
    ms_strbuild_printf(out, "%02x", b);
  }
}

typedef struct Rdn {
  const char *label; /* NULL for an unknown attribute */
  const MsString *values;
  size_t count;
  const Extra *extra;
} Rdn;

static void rdn_text(MsStrBuild *out, const Rdn *rdn) {
  for (size_t i = 0; i < rdn->count; i++) {
    if (i > 0) {
      ms_strbuild_append_byte(out, '+');
    }
    if (rdn->label == NULL) {
      unknown_attribute(out, rdn->extra);
      continue;
    }
    ms_strbuild_append_text(out, rdn->label);
    ms_strbuild_append_byte(out, '=');
    escape(out, ms_string_span(&rdn->values[i]));
  }
}

static void collect(const X509_NAME *name, Fields *fields) {
  const int count = X509_NAME_entry_count(name);
  for (int i = 0; i < count; i++) {
    const X509_NAME_ENTRY *entry = X509_NAME_get_entry(name, i);
    char oid[80];
    unsigned char *utf8 = NULL;
    const int length = ASN1_STRING_to_UTF8(&utf8, X509_NAME_ENTRY_get_data(entry));
    if (length < 0) {
      continue;
    }
    (void)OBJ_obj2txt(oid, sizeof oid, X509_NAME_ENTRY_get_object(entry), 1);
    fields_add(fields, ms_string_from_span(ms_span_of_text(oid)),
               ms_string_from_span(ms_span_of(utf8, (size_t)length)));
    OPENSSL_free(utf8);
  }
}

MsString ms_tls_dn_text(const X509_NAME *name) {
  Fields fields = {0};
  collect(name, &fields);
  MsList rdns = {0}; /* Rdn, in certificate order of the printed text reversed */
  const Extra *extra = (const Extra *)(const void *)fields.extra.ptr;
  for (size_t i = 0; i < fields.extra.len; i++) {
    const Rdn rdn = {NULL, NULL, 1, &extra[i]};
    ms_list_push(&rdns, sizeof rdn, &rdn);
  }
  for (int g = 0; g < GROUPS; g++) {
    if (fields.groups[g].len > 0) {
      const Rdn rdn = {group_labels[g], (const MsString *)(const void *)fields.groups[g].ptr,
                       fields.groups[g].len, NULL};
      ms_list_push(&rdns, sizeof rdn, &rdn);
    }
  }
  if (fields.has_common) {
    const Rdn rdn = {"CN", &fields.common, 1, NULL};
    ms_list_push(&rdns, sizeof rdn, &rdn);
  }
  if (fields.has_serial) {
    const Rdn rdn = {"SERIALNUMBER", &fields.serial, 1, NULL};
    ms_list_push(&rdns, sizeof rdn, &rdn);
  }
  MsStrBuild out = ms_strbuild_new();
  const Rdn *items = (const Rdn *)(const void *)rdns.ptr;
  for (size_t i = rdns.len; i > 0; i--) {
    if (i < rdns.len) {
      ms_strbuild_append_byte(&out, ',');
    }
    rdn_text(&out, &items[i - 1]);
  }
  ms_list_free(&rdns);
  fields_free(&fields);
  return ms_strbuild_finish(&out);
}
