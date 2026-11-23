/* The @std/net/url natives: components of a parsed URL, formatting, resolution and query strings, on the byte
 * oriented parser of url_parse.c. */
#include "base/alloc.h"
#include "base/chars.h"
#include "base/list.h"
#include "base/utf8.h"
#include "runtime/core/ucd.h"
#include "runtime/std/url.h"
#include "runtime/std/url_internal.h"

enum { MAX_PORT = 65535, REPLACEMENT_CHARACTER = 0xFFFD };

/* ---- the optional string of a record ---- */

static MsString none_string(void) {
  return (MsString){.low_bits = 0, .tagged = UINT64_C(2) << MS_STRING_TAG_SHIFT};
}

static bool is_some(const MsString *value) {
  return !(value->low_bits == 0 && value->tagged == none_string().tagged);
}

/* ---- text ---- */

static bool valid_text(MsSpan text) {
  return ms_utf8_is_valid(text.ptr, text.len);
}

/* A string from a builder's bytes, or false (InvalidData) when they are not UTF-8. */
static bool string_of(const MsStrBuild *bytes, MsString *out) {
  const MsSpan text = ms_strbuild_span(bytes);
  if (!valid_text(text)) {
    return false;
  }
  *out = ms_string_from_span(text);
  return true;
}

/* The lowercase of one scalar by the simple mapping: the first scalar of Rust's to_lowercase. */
static uint32_t lower_scalar(uint32_t scalar) {
  if (scalar < 0x80) {
    return ms_ascii_to_lower((uint8_t)scalar);
  }
  const int32_t field = ms_ucd_case_of(scalar)[0];
  if (field == 0) {
    return scalar;
  }
  if (field < MS_UCD_CASE_SPECIAL) {
    return (uint32_t)((int32_t)scalar + field);
  }
  return ms_ucd_case_pool[(uint32_t)field & 0xFFFFu];
}

/* Go's strings.ToLower for text that may hold invalid UTF-8: each bad byte becomes U+FFFD. */
static void go_lower(MsSpan text, MsStrBuild *out) {
  for (size_t at = 0; at < text.len;) {
    const MsRune scalar = ms_utf8_decode(text.ptr + at, text.len - at);
    const bool bad = scalar.rune == MS_RUNE_ERROR && scalar.width == 1;
    ms_strbuild_append_utf8(out, bad ? (uint32_t)REPLACEMENT_CHARACTER : lower_scalar(scalar.rune));
    at += scalar.width;
  }
}

/* Lowercases a hostname but keeps an IPv6 zone identifier (after the first `%`), which is case-sensitive. */
static void go_lower_host(MsSpan host, MsStrBuild *out) {
  size_t percent = host.len;
  (void)ms_span_find_byte(host, '%', &percent);
  go_lower(ms_span_of(host.ptr, percent), out);
  url_append(out, ms_span_of(host.ptr + percent, host.len - percent));
}

/* ---- components ---- */

static bool valid_query(MsSpan query) {
  for (size_t i = 0; i < query.len; i++) {
    const uint8_t c = query.ptr[i];
    if (c == '#' || c == ' ' || c < 0x20 || c == 0x7f) {
      return false;
    }
    if (c == '%' &&
        (i + 2 >= query.len || !ms_ascii_is_hex(query.ptr[i + 1]) || !ms_ascii_is_hex(query.ptr[i + 2]))) {
      return false;
    }
  }
  return true;
}

/* The port of "host:port" digits; false when it exceeds 65535. */
static bool parse_port(MsSpan digits, MsUrlPort *port) {
  int64_t value = 0;
  for (size_t i = 0; i < digits.len; i++) {
    value = value * 10 + (digits.ptr[i] - '0');
    if (value > MAX_PORT) {
      return false;
    }
  }
  port->present = digits.len != 0;
  port->value = value;
  return true;
}

static void url_release(MsUrl *url) {
  ms_string_release(&url->scheme);
  ms_string_release(&url->host);
  ms_string_release(&url->path);
  ms_string_release(&url->fragment);
  if (is_some(&url->query)) {
    ms_string_release(&url->query);
  }
}

/* The text fields of the record for `parts`; false when something is not valid text. */
static bool fill_texts(const UrlParts *parts, MsSpan hostname, MsUrl *out) {
  MsStrBuild scheme = ms_strbuild_new();
  MsStrBuild host = ms_strbuild_new();
  MsStrBuild path = ms_strbuild_new();
  go_lower(ms_strbuild_span(&parts->scheme), &scheme);
  go_lower_host(hostname, &host);
  url_escaped_path(parts, &path);
  out->scheme = ms_string_from_span(ms_strbuild_span(&scheme));
  out->host = ms_string_from_span(ms_strbuild_span(&host));
  out->query = none_string();
  const bool ok = string_of(&path, &out->path) && string_of(&parts->fragment, &out->fragment);
  if (ok && (parts->force_query || parts->raw_query.bytes.len != 0)) {
    out->query = ms_string_from_span(ms_strbuild_span(&parts->raw_query));
  }
  ms_strbuild_free(&scheme);
  ms_strbuild_free(&host);
  ms_strbuild_free(&path);
  return ok;
}

/* The record for `parts`, or InvalidData for user information, an opaque URL, no scheme, a bad port or text.
 */
static uint8_t components(const UrlParts *parts, MsUrl *out) {
  if (parts->has_user || parts->opaque.bytes.len != 0 || parts->scheme.bytes.len == 0) {
    return MS_STATUS_INVALID_DATA;
  }
  MsSpan hostname;
  MsSpan port_text;
  url_split_host_port(ms_strbuild_span(&parts->host), &hostname, &port_text);
  MsUrl url = {0};
  const bool bracketed = parts->host.bytes.len != 0 && parts->host.bytes.ptr[0] == '[';
  if (!parse_port(port_text, &url.port) || !valid_text(ms_strbuild_span(&parts->path)) ||
      !valid_text(ms_strbuild_span(&parts->fragment)) || !valid_query(ms_strbuild_span(&parts->raw_query)) ||
      (ms_span_has_byte(hostname, ':') && !bracketed)) {
    return MS_STATUS_INVALID_DATA;
  }
  url.omit_host = parts->omit_host;
  const bool ok = fill_texts(parts, hostname, &url);
  if (!ok) {
    url_release(&url);
    return MS_STATUS_INVALID_DATA;
  }
  *out = url;
  return MS_STATUS_OK;
}

uint8_t msstd_url_parse(const MsString *text, MsUrl *out) {
  UrlParts parts;
  uint8_t status = MS_STATUS_INVALID_DATA;
  if (url_parse(ms_string_span(text), &parts) && parts.scheme.bytes.len != 0 && !parts.has_user) {
    status = components(&parts, out);
  }
  url_parts_free(&parts);
  return status;
}

/* ---- rebuilding a URL from a record ---- */

static MsSpan field_span(const MsString *value) {
  return is_some(value) ? ms_string_span(value) : ms_span_of(NULL, 0);
}

/* The `UrlParts` of a record once its cheap checks pass (Go's JoinHostPort, path unescape, query and host
 * validity); false rejects it. */
static bool build_url(const MsUrl *v, UrlParts *url) {
  *url = (UrlParts){0};
  const MsSpan host = ms_string_span(&v->host);
  const bool bracket = ms_span_has_byte(host, ':');
  if (bracket) {
    ms_strbuild_append_byte(&url->host, '[');
  }
  url_append(&url->host, host);
  if (bracket) {
    ms_strbuild_append_byte(&url->host, ']');
  }
  if (v->port.present != 0) {
    if (v->port.value < 0 || v->port.value > MAX_PORT) {
      return false;
    }
    ms_strbuild_append_byte(&url->host, ':');
    ms_strbuild_append_u64(&url->host, (uint64_t)v->port.value);
  }
  const MsSpan raw = ms_string_span(&v->path);
  if (url->host.bytes.len == 0 && raw.len != 0 && raw.ptr[0] != '/') {
    return false;
  }
  if (!url_unescape(raw, URL_ENC_PATH_SEGMENT, &url->path) || !valid_text(ms_strbuild_span(&url->path))) {
    return false;
  }
  size_t percent = url->host.bytes.len;
  (void)ms_span_find_byte(ms_strbuild_span(&url->host), '%', &percent);
  const MsSpan query = field_span(&v->query);
  const MsSpan address = ms_span_of(url->host.bytes.ptr, percent);
  if (!valid_query(query) || ms_span_has_byte(address, ' ') || ms_span_has_byte(address, '<') ||
      ms_span_has_byte(address, '>') || ms_span_has_byte(address, '"')) {
    return false;
  }
  url_append(&url->scheme, ms_string_span(&v->scheme));
  url_append(&url->raw_path, raw);
  url_append(&url->raw_query, query);
  url_append(&url->fragment, ms_string_span(&v->fragment));
  url->omit_host = v->omit_host != 0;
  url->force_query = is_some(&v->query) && query.len == 0;
  return true;
}

/* ---- does a rendered URL read back? ---- */

static bool is_name_byte(uint8_t b) {
  return ms_ascii_is_alnum(b) || b == '-' || b == '.' || b == '_' || b == '~';
}

static bool is_scheme_byte(uint8_t b) {
  return ms_ascii_is_alnum(b) || b == '-' || b == '.' || b == '+';
}

static bool all_bytes(MsSpan text, bool (*accepts)(uint8_t)) {
  for (size_t i = 0; i < text.len; i++) {
    if (!accepts(text.ptr[i])) {
      return false;
    }
  }
  return true;
}

static bool begins(const MsStrBuild *bytes, const char *prefix) {
  return ms_span_starts_with(ms_strbuild_span(bytes), ms_span_of_text(prefix));
}

/* Whether rendering `u` is known to read back as a URL with the same scheme and no user information, without
 * parsing it: a valid scheme, a plain host name, and a path that cannot be re-read as an authority. */
static bool reads_back_plain(const UrlParts *u) {
  const MsSpan scheme = ms_strbuild_span(&u->scheme);
  const bool scheme_ok =
      scheme.len != 0 && ms_ascii_is_alpha(scheme.ptr[0]) && all_bytes(scheme, is_scheme_byte);
  MsSpan name;
  MsSpan port;
  url_split_host_port(ms_strbuild_span(&u->host), &name, &port);
  const bool plain_host = !begins(&u->host, "[") && all_bytes(name, is_name_byte);
  const bool rereads_path = u->host.bytes.len == 0 && (begins(&u->path, "//") || begins(&u->raw_path, "//"));
  return scheme_ok && plain_host && !rereads_path;
}

/* The reference check: parse what was rendered and require a hierarchical URL with the same scheme, no user
 * information and no host byte that would change the authority. */
static bool reparses(const UrlParts *u, MsSpan rendered) {
  UrlParts parsed;
  bool ok = url_parse(rendered, &parsed);
  ok = ok && parsed.scheme.bytes.len != 0 &&
       ms_ascii_equal_fold(ms_strbuild_span(&parsed.scheme), ms_strbuild_span(&u->scheme)) &&
       parsed.opaque.bytes.len == 0 && !parsed.has_user;
  const MsSpan host = ms_strbuild_span(&u->host);
  for (size_t i = 0; ok && i < host.len; i++) {
    const uint8_t c = host.ptr[i];
    ok = !(c == '/' || c == '@' || c == '\\' || c == '\r' || c == '\n');
  }
  url_parts_free(&parsed);
  return ok;
}

/* Rebuilds a URL from `v`, rejecting anything that would not parse back; `rendered` receives its text. */
static bool go_url(const MsUrl *v, UrlParts *url, MsStrBuild *rendered) {
  if (!build_url(v, url)) {
    return false;
  }
  url_render(url, rendered);
  return reads_back_plain(url) || reparses(url, ms_strbuild_span(rendered));
}

uint8_t msstd_url_format(const MsUrl *value, MsString *out) {
  UrlParts url;
  MsStrBuild text = ms_strbuild_new();
  uint8_t status = MS_STATUS_INVALID_INPUT;
  if (go_url(value, &url, &text)) {
    /* A bare scheme would read as an opaque URL, so an empty hierarchical part keeps `//` unless the URL was
     * read without one. */
    MsStrBuild full = ms_strbuild_new();
    const MsSpan rendered = ms_strbuild_span(&text);
    const size_t at = url.scheme.bytes.len + 1;
    const bool slashes = url.host.bytes.len == 0 && url.path.bytes.len == 0 && !url.omit_host;
    url_append(&full, ms_span_of(rendered.ptr, slashes ? at : rendered.len));
    if (slashes) {
      ms_strbuild_append_text(&full, "//");
      url_append(&full, ms_span_of(rendered.ptr + at, rendered.len - at));
    }
    status = string_of(&full, out) ? MS_STATUS_OK : MS_STATUS_INVALID_DATA;
    ms_strbuild_free(&full);
  }
  url_parts_free(&url);
  ms_strbuild_free(&text);
  return status;
}

uint8_t msstd_url_resolve(const MsUrl *base, const MsString *reference, MsUrl *out) {
  UrlParts b;
  MsStrBuild text = ms_strbuild_new();
  uint8_t status = MS_STATUS_INVALID_INPUT;
  if (go_url(base, &b, &text)) {
    UrlParts r;
    status = MS_STATUS_INVALID_DATA;
    if (url_parse(ms_string_span(reference), &r) && !r.has_user) {
      UrlParts resolved;
      url_resolve_reference(&b, &r, &resolved);
      status = components(&resolved, out);
      url_parts_free(&resolved);
    }
    url_parts_free(&r);
  }
  url_parts_free(&b);
  ms_strbuild_free(&text);
  return status;
}

/* ---- components and queries ---- */

static int hex_value(uint8_t c) {
  return c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10;
}

void msstd_url_encode_component(const MsString *text, MsString *out) {
  static const char DIGITS[] = "0123456789ABCDEF";
  const MsSpan span = ms_string_span(text);
  MsStrBuild result = ms_strbuild_new();
  for (size_t i = 0; i < span.len; i++) {
    const uint8_t c = span.ptr[i];
    if (ms_ascii_is_alnum(c) || c == '-' || c == '.' || c == '_' || c == '~') {
      ms_strbuild_append_byte(&result, c);
    } else {
      ms_strbuild_append_byte(&result, '%');
      ms_strbuild_append_byte(&result, (uint8_t)DIGITS[c >> 4]);
      ms_strbuild_append_byte(&result, (uint8_t)DIGITS[c & 15]);
    }
  }
  *out = ms_strbuild_finish(&result);
  ms_strbuild_free(&result);
}

uint8_t msstd_url_decode_component(const MsString *text, MsString *out) {
  const MsSpan span = ms_string_span(text);
  MsStrBuild result = ms_strbuild_new();
  /* `+` stays a plus: only escapes are decoded. */
  bool ok = true;
  for (size_t i = 0; ok && i < span.len;) {
    if (span.ptr[i] != '%') {
      ms_strbuild_append_byte(&result, span.ptr[i++]);
      continue;
    }
    ok = i + 3 <= span.len && ms_ascii_is_hex(span.ptr[i + 1]) && ms_ascii_is_hex(span.ptr[i + 2]);
    if (ok) {
      ms_strbuild_append_byte(&result,
                              (uint8_t)(hex_value(span.ptr[i + 1]) * 16 + hex_value(span.ptr[i + 2])));
      i += 3;
    }
  }
  const uint8_t status = ok && string_of(&result, out) ? MS_STATUS_OK : MS_STATUS_INVALID_DATA;
  ms_strbuild_free(&result);
  return status;
}

/* One `key=value` part of a query as decoded text; false (InvalidData) when it is malformed. */
static bool query_entry(MsSpan part, MsQueryEntry *entry) {
  size_t equals = part.len;
  (void)ms_span_find_byte(part, '=', &equals);
  const MsSpan key = ms_span_of(part.ptr, equals);
  const MsSpan value =
      equals < part.len ? ms_span_of(part.ptr + equals + 1, part.len - equals - 1) : ms_span_of(NULL, 0);
  MsStrBuild decoded_key = ms_strbuild_new();
  MsStrBuild decoded_value = ms_strbuild_new();
  const bool ok = url_unescape(key, URL_ENC_QUERY_COMPONENT, &decoded_key) &&
                  url_unescape(value, URL_ENC_QUERY_COMPONENT, &decoded_value) &&
                  valid_text(ms_strbuild_span(&decoded_key)) && valid_text(ms_strbuild_span(&decoded_value));
  if (ok) {
    entry->key = ms_string_from_span(ms_strbuild_span(&decoded_key));
    entry->value = ms_string_from_span(ms_strbuild_span(&decoded_value));
  }
  ms_strbuild_free(&decoded_key);
  ms_strbuild_free(&decoded_value);
  return ok;
}

static void release_entries(MsBytes *list) {
  for (size_t i = 0; i < list->len; i++) {
    MsQueryEntry entry;
    __builtin_memcpy(&entry, list->ptr + i * sizeof entry, sizeof entry);
    ms_string_release(&entry.key);
    ms_string_release(&entry.value);
  }
  ms_list_free(list);
}

uint8_t msstd_url_parse_query(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out) {
  if (has_max != 0 && max < 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  const size_t limit = has_max != 0 ? (size_t)max : SIZE_MAX;
  const MsSpan query = ms_string_span(text);
  MsBytes items = {0};
  uint8_t status = MS_STATUS_OK;
  for (size_t start = 0; status == MS_STATUS_OK && start <= query.len && query.len != 0;) {
    size_t amp = query.len - start;
    (void)ms_span_find_byte(ms_span_of(query.ptr + start, query.len - start), '&', &amp);
    const MsSpan part = ms_span_of(query.ptr + start, amp);
    start += amp + 1;
    if (part.len == 0) {
      continue;
    }
    MsQueryEntry entry;
    if (items.len >= limit) {
      status = MS_STATUS_LIMIT_EXCEEDED;
    } else if (!query_entry(part, &entry)) {
      status = MS_STATUS_INVALID_DATA;
    } else {
      ms_list_push(&items, sizeof entry, &entry);
    }
  }
  if (status != MS_STATUS_OK) {
    release_entries(&items);
    return status;
  }
  *out = items;
  return MS_STATUS_OK;
}

void msstd_url_format_query(const MsBytes *entries, MsString *out) {
  MsStrBuild result = ms_strbuild_new();
  const size_t count = entries->len;
  for (size_t i = 0; i < count; i++) {
    MsQueryEntry entry;
    __builtin_memcpy(&entry, entries->ptr + i * sizeof entry, sizeof entry);
    if (i > 0) {
      ms_strbuild_append_byte(&result, '&');
    }
    url_escape(ms_string_span(&entry.key), URL_ENC_QUERY_COMPONENT, &result);
    ms_strbuild_append_byte(&result, '=');
    url_escape(ms_string_span(&entry.value), URL_ENC_QUERY_COMPONENT, &result);
  }
  *out = ms_strbuild_finish(&result);
  ms_strbuild_free(&result);
}
