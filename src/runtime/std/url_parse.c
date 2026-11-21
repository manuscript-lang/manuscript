/* Go's url.Parse over byte vectors: scheme, authority, path, query and fragment. */
#include "base/chars.h"
#include "runtime/std/url_internal.h"

void url_parts_free(UrlParts *parts) {
  MsStrBuild *fields[] = {&parts->scheme,   &parts->opaque,    &parts->host,     &parts->path,
                          &parts->raw_path, &parts->raw_query, &parts->fragment, &parts->raw_fragment,
                          &parts->username, &parts->password};
  for (size_t i = 0; i < sizeof fields / sizeof fields[0]; i++) {
    ms_strbuild_free(fields[i]);
  }
}

void url_parts_clone(const UrlParts *source, UrlParts *out) {
  *out = *source;
  const MsStrBuild *from[] = {&source->scheme,   &source->opaque,    &source->host,     &source->path,
                              &source->raw_path, &source->raw_query, &source->fragment, &source->raw_fragment,
                              &source->username, &source->password};
  MsStrBuild *to[] = {&out->scheme,    &out->opaque,   &out->host,         &out->path,     &out->raw_path,
                      &out->raw_query, &out->fragment, &out->raw_fragment, &out->username, &out->password};
  for (size_t i = 0; i < sizeof to / sizeof to[0]; i++) {
    *to[i] = ms_strbuild_new();
    url_append(to[i], ms_strbuild_span(from[i]));
  }
}

/* Splits at the first `sep`: `before` is everything when there is none. */
static bool cut(MsSpan text, uint8_t sep, MsSpan *before, MsSpan *after) {
  size_t at = 0;
  if (!url_find_first(text, sep, &at)) {
    *before = text;
    *after = ms_span_of(NULL, 0);
    return false;
  }
  *before = ms_span_of(text.ptr, at);
  *after = ms_span_of(text.ptr + at + 1, text.len - at - 1);
  return true;
}

static MsSpan tail(MsSpan text, size_t from) {
  return ms_span_of(text.ptr + from, text.len - from);
}

static bool starts_with(MsSpan text, const char *prefix) {
  return ms_span_starts_with(text, ms_span_of_text(prefix));
}

/* Go's getScheme: the scheme (empty for none) and the rest; false for an empty scheme before `:`. */
static bool get_scheme(MsSpan raw, MsSpan *scheme, MsSpan *rest) {
  *scheme = ms_span_of(NULL, 0);
  *rest = raw;
  for (size_t i = 0; i < raw.len; i++) {
    const uint8_t c = raw.ptr[i];
    if (ms_ascii_is_alpha(c)) {
      continue;
    }
    if ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') {
      if (i == 0) {
        return true;
      }
      continue;
    }
    if (c == ':') {
      if (i == 0) {
        return false;
      }
      *scheme = ms_span_of(raw.ptr, i);
      *rest = tail(raw, i + 1);
      return true;
    }
    return true;
  }
  return true;
}

static bool has_ctl(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] < ' ' || text.ptr[i] == 0x7f) {
      return true;
    }
  }
  return false;
}

static bool valid_userinfo(MsSpan text) {
  static const char ALLOWED[] = "-._:~!$&'()*+,;=%@";
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    bool allowed = ms_ascii_is_alnum(c);
    for (size_t k = 0; ALLOWED[k] != 0; k++) {
      allowed = allowed || (uint8_t)ALLOWED[k] == c;
    }
    if (!allowed) {
      return false;
    }
  }
  return true;
}

/* Appends the host with its zone unescaped by the zone rules; `close` is the index of the last `]`. */
static bool parse_bracketed_host(MsSpan host, size_t close, MsStrBuild *out) {
  for (size_t i = 0; i + 3 <= close; i++) {
    if (host.ptr[i] == '%' && host.ptr[i + 1] == '2' && host.ptr[i + 2] == '5') {
      return url_unescape(ms_span_of(host.ptr, i), URL_ENC_HOST, out) &&
             url_unescape(ms_span_of(host.ptr + i, close - i), URL_ENC_ZONE, out) &&
             url_unescape(tail(host, close), URL_ENC_HOST, out);
    }
  }
  return url_unescape(host, URL_ENC_HOST, out);
}

static bool parse_host(MsSpan host, MsStrBuild *out) {
  size_t at = 0;
  if (starts_with(host, "[")) {
    if (!url_find_last(host, ']', &at) || !url_valid_optional_port(tail(host, at + 1))) {
      return false;
    }
    return parse_bracketed_host(host, at, out);
  }
  if (url_find_last(host, ':', &at) && !url_valid_optional_port(tail(host, at))) {
    return false;
  }
  return url_unescape(host, URL_ENC_HOST, out);
}

static bool parse_authority(MsSpan authority, UrlParts *url) {
  size_t at = 0;
  const bool has_at = url_find_last(authority, '@', &at);
  if (!parse_host(has_at ? tail(authority, at + 1) : authority, &url->host)) {
    return false;
  }
  if (!has_at) {
    return true;
  }
  const MsSpan userinfo = ms_span_of(authority.ptr, at);
  if (!valid_userinfo(userinfo)) {
    return false;
  }
  MsSpan name;
  MsSpan password;
  url->has_user = true;
  url->password_set = cut(userinfo, ':', &name, &password);
  return url_unescape(name, URL_ENC_USER_PASSWORD, &url->username) &&
         (!url->password_set || url_unescape(password, URL_ENC_USER_PASSWORD, &url->password));
}

bool url_set_path(UrlParts *url, MsSpan path) {
  MsStrBuild decoded = ms_strbuild_new();
  MsStrBuild again = ms_strbuild_new();
  const bool canonical = url_is_canonical(path, URL_ENC_PATH);
  bool ok = true;
  if (canonical) {
    url_append(&decoded, path);
  } else {
    ok = url_unescape(path, URL_ENC_PATH, &decoded);
    url_escape(ms_strbuild_span(&decoded), URL_ENC_PATH, &again);
  }
  if (ok) {
    url_truncate(&url->path, 0);
    url_append(&url->path, ms_strbuild_span(&decoded));
    url_truncate(&url->raw_path, 0);
    if (!canonical && !url_equals(&again, path)) {
      url_append(&url->raw_path, path);
    }
  }
  ms_strbuild_free(&decoded);
  ms_strbuild_free(&again);
  return ok;
}

static bool set_fragment(UrlParts *url, MsSpan fragment) {
  if (url_is_canonical(fragment, URL_ENC_FRAGMENT)) {
    url_append(&url->fragment, fragment);
    return true;
  }
  if (!url_unescape(fragment, URL_ENC_FRAGMENT, &url->fragment)) {
    return false;
  }
  MsStrBuild again = ms_strbuild_new();
  url_escape(ms_strbuild_span(&url->fragment), URL_ENC_FRAGMENT, &again);
  if (!url_equals(&again, fragment)) {
    url_append(&url->raw_fragment, fragment);
  }
  ms_strbuild_free(&again);
  return true;
}

static size_t count_byte(MsSpan text, uint8_t byte) {
  size_t count = 0;
  for (size_t i = 0; i < text.len; i++) {
    count += text.ptr[i] == byte ? 1u : 0u;
  }
  return count;
}

/* The part after the scheme: query first, then the authority and path. `rest` starts after the scheme. */
static bool parse_hierarchy(MsSpan rest, UrlParts *url) {
  if (starts_with(rest, "//") && !(starts_with(rest, "///") && url->scheme.bytes.len == 0)) {
    MsSpan authority = tail(rest, 2);
    rest = ms_span_of(NULL, 0);
    size_t slash = 0;
    if (url_find_first(authority, '/', &slash)) {
      rest = tail(authority, slash);
      authority = ms_span_of(authority.ptr, slash);
    }
    if (!parse_authority(authority, url)) {
      return false;
    }
  } else if (url->scheme.bytes.len != 0 && starts_with(rest, "/")) {
    url->omit_host = true;
  }
  return url_set_path(url, rest);
}

static bool parse_inner(MsSpan raw, UrlParts *url) {
  if (has_ctl(raw)) {
    return false;
  }
  if (ms_span_is_text(raw, "*")) {
    url_append(&url->path, raw);
    return true;
  }
  MsSpan scheme;
  MsSpan rest;
  if (!get_scheme(raw, &scheme, &rest)) {
    return false;
  }
  for (size_t i = 0; i < scheme.len; i++) {
    ms_strbuild_append_byte(&url->scheme, ms_ascii_to_lower(scheme.ptr[i]));
  }
  if (rest.len > 0 && rest.ptr[rest.len - 1] == '?' && count_byte(rest, '?') == 1) {
    url->force_query = true;
    rest = ms_span_of(rest.ptr, rest.len - 1);
  } else {
    MsSpan before;
    MsSpan query;
    (void)cut(rest, '?', &before, &query);
    rest = before;
    url_append(&url->raw_query, query);
  }
  if (!starts_with(rest, "/")) {
    if (url->scheme.bytes.len != 0) {
      url_append(&url->opaque, rest);
      url->omit_host = true; /* no `//` was written: `mailto:?subject=hi` */
      return true;
    }
    MsSpan segment;
    MsSpan after;
    (void)cut(rest, '/', &segment, &after);
    if (url_has_byte(segment, ':')) {
      return false;
    }
  }
  return parse_hierarchy(rest, url);
}

bool url_parse(MsSpan raw, UrlParts *out) {
  *out = (UrlParts){0};
  MsSpan before;
  MsSpan fragment;
  (void)cut(raw, '#', &before, &fragment);
  if (!parse_inner(before, out)) {
    return false;
  }
  return fragment.len == 0 || set_fragment(out, fragment);
}
