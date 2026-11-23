/* lsp/lsp_uri.c: `file:` and `manuscript-stdlib:` URIs. Port of crates/ms-lsp/src/uri.rs. */
#include <ctype.h>
#include <string.h>

#include "base/utf8.h"
#include "lsp/lsp_internal.h"

bool lsp_uri_is_standard_library(MsSpan uri) {
  return ms_span_starts_with(uri, ms_span_of_text("manuscript-stdlib:"));
}

static int hex_value(uint8_t c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

/* Percent-decodes `text` into `out`; false for a bad escape or bytes that are not UTF-8. */
static bool unescape(MsSpan text, MsStrBuild *out) {
  for (size_t at = 0; at < text.len;) {
    if (text.ptr[at] != '%') {
      ms_strbuild_append_byte(out, text.ptr[at++]);
      continue;
    }
    if (at + 3 > text.len) return false;
    const int high = hex_value(text.ptr[at + 1]), low = hex_value(text.ptr[at + 2]);
    if (high < 0 || low < 0) return false;
    ms_strbuild_append_byte(out, (uint8_t)(high * 16 + low));
    at += 3;
  }
  const MsSpan decoded = ms_strbuild_span(out);
  return ms_utf8_is_valid(decoded.ptr, decoded.len);
}

static bool is_file_scheme(const uint8_t *text, size_t length) {
  if (length != 4) return false;
  for (size_t i = 0; i < 4; i++) {
    if (tolower(text[i]) != "file"[i]) return false;
  }
  return true;
}

typedef struct Url {
  bool scheme_file;
  MsSpan host;
  MsStrBuild path;
} Url;

/* Parses a URI the way Go's url.Parse does for the shapes editors send. False when it is malformed. */
static bool parse(MsSpan raw, Url *url) {
  *url = (Url){.path = ms_strbuild_new()};
  MsSpan rest = raw;
  const uint8_t *colon = memchr(rest.ptr, ':', rest.len);
  bool has_scheme = false;
  if (colon != NULL) {
    const size_t length = (size_t)(colon - rest.ptr);
    bool valid = length > 0 && isalpha(rest.ptr[0]);
    for (size_t i = 0; valid && i < length; i++) {
      const uint8_t c = rest.ptr[i];
      valid = isalnum(c) || c == '+' || c == '-' || c == '.';
    }
    if (valid) {
      has_scheme = true;
      url->scheme_file = is_file_scheme(rest.ptr, length);
      rest = ms_span_of(colon + 1, rest.len - length - 1);
    } else if (length == 0) {
      return false;
    }
  }
  const uint8_t *cut = memchr(rest.ptr, '#', rest.len);
  if (cut != NULL) rest.len = (size_t)(cut - rest.ptr);
  cut = memchr(rest.ptr, '?', rest.len);
  if (cut != NULL) rest.len = (size_t)(cut - rest.ptr);
  if (rest.len >= 2 && rest.ptr[0] == '/' && rest.ptr[1] == '/') {
    const MsSpan after = ms_span_of(rest.ptr + 2, rest.len - 2);
    const uint8_t *slash = memchr(after.ptr, '/', after.len);
    const size_t end = slash == NULL ? after.len : (size_t)(slash - after.ptr);
    url->host = ms_span_of(after.ptr, end);
    rest = ms_span_of(after.ptr + end, after.len - end);
  } else if (!has_scheme && memchr(rest.ptr, ':', rest.len) != NULL) {
    const uint8_t *slash = memchr(rest.ptr, '/', rest.len);
    const size_t first = slash == NULL ? rest.len : (size_t)(slash - rest.ptr);
    if (memchr(rest.ptr, ':', first) != NULL) return false;
  }
  return unescape(rest, &url->path);
}

bool lsp_uri_is_malformed_file(MsSpan uri) {
  if (uri.len < 5) return false;
  for (size_t i = 0; i < 5; i++) {
    if (tolower(uri.ptr[i]) != "file:"[i]) return false;
  }
  Url url;
  const bool ok = parse(uri, &url);
  ms_strbuild_free(&url.path);
  return !ok;
}

void lsp_uri_filename(MsSpan uri, MsStrBuild *out) {
  Url url;
  if (!parse(uri, &url) || !url.scheme_file) {
    ms_strbuild_append(out, uri);
    ms_strbuild_free(&url.path);
    return;
  }
  MsSpan path = ms_strbuild_span(&url.path);
#ifdef _WIN32
  if (url.host.len > 0) {
    ms_strbuild_append_text(out, "//");
    ms_strbuild_append(out, url.host);
    ms_strbuild_append(out, path);
  } else {
    /* `/D:/dir` is the drive path `D:/dir`. */
    const bool drive = path.len >= 3 && path.ptr[0] == '/' && isalpha(path.ptr[1]) && path.ptr[2] == ':' &&
                       (path.len == 3 || path.ptr[3] == '/');
    ms_strbuild_append(out, drive ? ms_span_of(path.ptr + 1, path.len - 1) : path);
  }
#else
  ms_strbuild_append(out, path);
#endif
  ms_strbuild_free(&url.path);
}

static void escape_path(MsStrBuild *out, MsSpan path) {
  for (size_t i = 0; i < path.len; i++) {
    const uint8_t b = path.ptr[i];
    if (isalnum(b) || (b != 0 && memchr("-_.~$&+,/:;=@", b, 13) != NULL)) ms_strbuild_append_byte(out, b);
    else ms_strbuild_printf(out, "%%%02X", (unsigned)b);
  }
}

void lsp_file_uri(MsSpan path, MsStrBuild *out) {
  ms_strbuild_append_text(out, "file://");
#ifdef _WIN32
  MsStrBuild fixed = ms_strbuild_new();
  for (size_t i = 0; i < path.len; i++) ms_strbuild_append_byte(&fixed, path.ptr[i] == '\\' ? '/' : path.ptr[i]);
  MsSpan p = ms_strbuild_span(&fixed);
  if (ms_span_starts_with(p, ms_span_of_text("//?/UNC/"))) {
    escape_path(out, ms_span_of(p.ptr + 8, p.len - 8));
    ms_strbuild_free(&fixed);
    return;
  }
  if (ms_span_starts_with(p, ms_span_of_text("//?/"))) p = ms_span_of(p.ptr + 4, p.len - 4);
  if (p.len >= 2 && p.ptr[0] != '/' && p.ptr[1] == ':') ms_strbuild_append_byte(out, '/');
  escape_path(out, p);
  ms_strbuild_free(&fixed);
#else
  escape_path(out, path);
#endif
}
