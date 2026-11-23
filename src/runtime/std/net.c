/* runtime/std/net.c: IpAddress and Cidr objects and the network diagnostic texts. */
#include "runtime/std/shape_json.h"
#include "runtime/std/net.h"

#include "base/alloc.h"
#include "base/cstr.h"
#include "runtime/std/net_ip.h"

typedef struct IpCell {
  MsObj header;
  MsIp ip;
} IpCell;

typedef struct CidrCell {
  MsObj header;
  MsCidr cidr;
} CidrCell;

static MsObj *ip_clone(MsObj *object) {
  IpCell *copy = ms_alloc(sizeof *copy);
  *copy = *(const IpCell *)object;
  return &copy->header;
}

static MsObj *cidr_clone(MsObj *object) {
  CidrCell *copy = ms_alloc(sizeof *copy);
  *copy = *(const CidrCell *)object;
  return &copy->header;
}

static void cell_drop(MsObj *object) {
  ms_free(object);
}

static MsObj *ip_new(const MsIp *ip) {
  IpCell *cell = ms_alloc(sizeof *cell);
  *cell = (IpCell){.header = {.clone = ip_clone, .drop = cell_drop}, .ip = *ip};
  return &cell->header;
}

static MsObj *cidr_new(const MsCidr *cidr) {
  CidrCell *cell = ms_alloc(sizeof *cell);
  *cell = (CidrCell){.header = {.clone = cidr_clone, .drop = cell_drop}, .cidr = *cidr};
  return &cell->header;
}

static void finish_text(MsStrBuild *text, MsString *out) {
  *out = ms_strbuild_finish(text);
  ms_strbuild_free(text);
}

static void static_text(const char *text, MsString *out) {
  *out = ms_string_from_span(ms_span_of_text(text));
}

uint8_t msstd_json_dec_ip(const MsString *text, MsObj **out) {
  MsIp ip = {0};
  if (!ms_ip_parse(ms_string_span(text), &ip)) {
    return MS_STATUS_INVALID_INPUT;
  }
  ms_ip_normalize(&ip);
  *out = ip_new(&ip);
  return MS_STATUS_OK;
}

uint8_t msstd_json_dec_cidr(const MsString *text, MsObj **out) {
  MsCidr cidr = {0};
  if (!ms_cidr_parse(ms_string_span(text), &cidr)) {
    return MS_STATUS_INVALID_INPUT;
  }
  *out = cidr_new(&cidr);
  return MS_STATUS_OK;
}

uint8_t msstd_net_parse_ip(const MsString *text, MsObj **out, MsString *err) {
  (void)err;
  return msstd_json_dec_ip(text, out) == MS_STATUS_OK ? MS_STATUS_OK : MS_STATUS_INVALID_DATA;
}

uint8_t msstd_net_parse_cidr(const MsString *text, MsObj **out, MsString *err) {
  (void)err;
  return msstd_json_dec_cidr(text, out) == MS_STATUS_OK ? MS_STATUS_OK : MS_STATUS_INVALID_DATA;
}

uint8_t msstd_net_contains_ip(const MsObj *cidr, const MsObj *ip, uint8_t *out) {
  *out = ms_cidr_contains(&((const CidrCell *)cidr)->cidr, &((const IpCell *)ip)->ip);
  return MS_STATUS_OK;
}

void msstd_net_ip_address_text(const MsObj *ip, MsString *out) {
  MsStrBuild text = ms_strbuild_new();
  ms_ip_text(&((const IpCell *)ip)->ip, &text);
  finish_text(&text, out);
}

uint8_t msstd_net_ip_address_family(const MsObj *ip) {
  return ((const IpCell *)ip)->ip.v6;
}

void msstd_net_cidr_text(const MsObj *cidr, MsString *out) {
  MsStrBuild text = ms_strbuild_new();
  ms_cidr_text(&((const CidrCell *)cidr)->cidr, &text);
  finish_text(&text, out);
}

void msstd_net_ip_family_text(uint8_t family, MsString *out) {
  static_text(family == 0 ? "IPv4" : "IPv6", out);
}

void msstd_net_dns_kind_text(uint8_t kind, MsString *out) {
  static const char *const names[] = {"A", "AAAA", "CNAME", "MX", "NS", "TXT", "PTR", "SRV"};
  static_text(kind < sizeof names / sizeof names[0] ? names[kind] : "", out);
}

static const char *reason_of(uint8_t status) {
  switch (status) {
  case MS_STATUS_INVALID_INPUT:
    return "invalid input";
  case MS_STATUS_INVALID_DATA:
    return "invalid data";
  case MS_STATUS_LIMIT_EXCEEDED:
    return "limit exceeded";
  case MS_STATUS_PERMISSION_DENIED:
    return "permission denied";
  case MS_STATUS_UNSUPPORTED:
    return "operation not supported";
  case MS_STATUS_CLOSED:
    return "resource is closed";
  case MS_STATUS_TIMED_OUT:
    return "operation timed out";
  default:
    return NULL;
  }
}

void msstd_net_error_message(uint8_t status, uint8_t has_failed, const MsString *failed, MsString *out) {
  const char *reason = reason_of(status);
  if (reason == NULL) {
    *out = has_failed ? ms_string_clone(failed) : ms_string_empty();
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "network: ");
  ms_strbuild_append_text(&text, reason);
  finish_text(&text, out);
}

static const MsObjectCodec OBJECT_CODECS[] = {
    {"IpAddress", msstd_net_ip_address_text, msstd_json_dec_ip},
    {"Cidr", msstd_net_cidr_text, msstd_json_dec_cidr},
};

const MsObjectCodec *ms_object_codec(const char *name) {
  for (size_t index = 0; index < sizeof OBJECT_CODECS / sizeof OBJECT_CODECS[0]; index++) {
    if (ms_cstr_equal(OBJECT_CODECS[index].name, name)) {
      return &OBJECT_CODECS[index];
    }
  }
  return NULL;
}
