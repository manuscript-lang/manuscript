/* Go's URL.String, URL.ResolveReference and resolvePath over byte vectors. */
#include "runtime/std/url_internal.h"

static void user_render(const UrlParts *url, MsStrBuild *out) {
  url_escape(ms_strbuild_span(&url->username), URL_ENC_USER_PASSWORD, out);
  if (url->password_set) {
    ms_strbuild_append_byte(out, ':');
    url_escape(ms_strbuild_span(&url->password), URL_ENC_USER_PASSWORD, out);
  }
}

/* Whether `raw` is a non-empty valid encoding of exactly `plain` in `mode`. */
static bool raw_matches(const MsStrBuild *raw, const MsStrBuild *plain, UrlEnc mode) {
  const MsSpan raw_span = ms_strbuild_span(raw);
  if (raw_span.len == 0 || !url_valid_encoded(raw_span, mode)) {
    return false;
  }
  MsStrBuild decoded = ms_strbuild_new();
  const bool same = url_unescape(raw_span, mode, &decoded) && url_equals(&decoded, ms_strbuild_span(plain));
  ms_strbuild_free(&decoded);
  return same;
}

void url_escaped_path(const UrlParts *url, MsStrBuild *out) {
  if (raw_matches(&url->raw_path, &url->path, URL_ENC_PATH)) {
    url_append(out, ms_strbuild_span(&url->raw_path));
  } else if (url_equals(&url->path, ms_span_of_text("*"))) {
    url_append(out, ms_strbuild_span(&url->path));
  } else {
    url_escape(ms_strbuild_span(&url->path), URL_ENC_PATH, out);
  }
}

static void escaped_fragment(const UrlParts *url, MsStrBuild *out) {
  if (raw_matches(&url->raw_fragment, &url->fragment, URL_ENC_FRAGMENT)) {
    url_append(out, ms_strbuild_span(&url->raw_fragment));
  } else {
    url_escape(ms_strbuild_span(&url->fragment), URL_ENC_FRAGMENT, out);
  }
}

/* The authority and path of a hierarchical URL. */
static void render_hierarchy(const UrlParts *url, MsStrBuild *out) {
  const bool host_empty = url->host.bytes.len == 0;
  if ((url->scheme.bytes.len != 0 || !host_empty || url->has_user) &&
      !(url->omit_host && host_empty && !url->has_user)) {
    if (!host_empty || url->path.bytes.len != 0 || url->has_user) {
      ms_strbuild_append_text(out, "//");
    }
    if (url->has_user) {
      user_render(url, out);
      ms_strbuild_append_byte(out, '@');
    }
    url_escape(ms_strbuild_span(&url->host), URL_ENC_HOST, out);
  }
  MsStrBuild path = ms_strbuild_new();
  url_escaped_path(url, &path);
  const MsSpan text = ms_strbuild_span(&path);
  if (text.len != 0 && text.ptr[0] != '/' && !host_empty) {
    ms_strbuild_append_byte(out, '/');
  }
  size_t slash = text.len;
  (void)ms_span_find_byte(text, '/', &slash);
  if (ms_strbuild_length(out) == 0 && ms_span_has_byte(ms_span_of(text.ptr, slash), ':')) {
    ms_strbuild_append_text(out, "./");
  }
  url_append(out, text);
  ms_strbuild_free(&path);
}

void url_render(const UrlParts *url, MsStrBuild *out) {
  if (url->scheme.bytes.len != 0) {
    url_append(out, ms_strbuild_span(&url->scheme));
    ms_strbuild_append_byte(out, ':');
  }
  if (url->opaque.bytes.len != 0) {
    url_append(out, ms_strbuild_span(&url->opaque));
  } else {
    render_hierarchy(url, out);
  }
  if (url->force_query || url->raw_query.bytes.len != 0) {
    ms_strbuild_append_byte(out, '?');
    url_append(out, ms_strbuild_span(&url->raw_query));
  }
  if (url->fragment.bytes.len != 0) {
    ms_strbuild_append_byte(out, '#');
    escaped_fragment(url, out);
  }
}

/* Go's resolvePath: `base` and `reference` are escaped paths. */
static void resolve_path(MsSpan base, MsSpan reference, MsStrBuild *out) {
  MsStrBuild full = ms_strbuild_new();
  if (reference.len == 0) {
    url_append(&full, base);
  } else if (reference.ptr[0] != '/') {
    size_t slash = 0;
    const size_t keep = url_find_last(base, '/', &slash) ? slash + 1 : 0;
    url_append(&full, ms_span_of(base.ptr, keep));
    url_append(&full, reference);
  } else {
    url_append(&full, reference);
  }
  if (ms_strbuild_length(&full) == 0) {
    ms_strbuild_free(&full);
    return;
  }
  MsStrBuild dst = ms_strbuild_new();
  ms_strbuild_append_byte(&dst, '/');
  bool first = true;
  MsSpan remaining = ms_strbuild_span(&full);
  MsSpan element = ms_span_of(NULL, 0);
  for (bool more = true; more;) {
    size_t slash = 0;
    more = ms_span_find_byte(remaining, '/', &slash);
    element = more ? ms_span_of(remaining.ptr, slash) : remaining;
    remaining = more ? ms_span_of(remaining.ptr + slash + 1, remaining.len - slash - 1) : remaining;
    if (ms_span_is_text(element, ".")) {
      first = false;
    } else if (ms_span_is_text(element, "..")) {
      const MsSpan body = ms_span_of(ms_strbuild_span(&dst).ptr + 1, ms_strbuild_length(&dst) - 1);
      size_t last = 0;
      const bool found = url_find_last(body, '/', &last);
      url_truncate(&dst, found ? last + 1 : 1);
      first = found ? first : true;
    } else {
      if (!first) {
        ms_strbuild_append_byte(&dst, '/');
      }
      url_append(&dst, element);
      first = false;
    }
  }
  if (ms_span_is_text(element, ".") || ms_span_is_text(element, "..")) {
    ms_strbuild_append_byte(&dst, '/');
  }
  const MsSpan result = ms_strbuild_span(&dst);
  const bool drop_first = result.len > 1 && result.ptr[1] == '/';
  url_append(out, ms_span_of(result.ptr + (drop_first ? 1 : 0), result.len - (drop_first ? 1 : 0)));
  ms_strbuild_free(&dst);
  ms_strbuild_free(&full);
}

/* Replaces the path of `url` with the resolution of `base` and `reference`. */
static void set_resolved(UrlParts *url, const MsStrBuild *base, const MsStrBuild *reference) {
  MsStrBuild resolved = ms_strbuild_new();
  resolve_path(ms_strbuild_span(base), ms_strbuild_span(reference), &resolved);
  (void)url_set_path(url, ms_strbuild_span(&resolved));
  ms_strbuild_free(&resolved);
}

static void clear_authority(UrlParts *url) {
  url->has_user = false;
  url->password_set = false;
  url_truncate(&url->username, 0);
  url_truncate(&url->password, 0);
  url_truncate(&url->host, 0);
  url_truncate(&url->path, 0);
}

static void replace(MsStrBuild *target, const MsStrBuild *value) {
  url_truncate(target, 0);
  url_append(target, ms_strbuild_span(value));
}

void url_resolve_reference(const UrlParts *base, const UrlParts *r, UrlParts *url) {
  url_parts_clone(r, url);
  MsStrBuild reference_path = ms_strbuild_new();
  url_escaped_path(r, &reference_path);
  MsStrBuild empty = ms_strbuild_new();
  if (r->scheme.bytes.len == 0) {
    replace(&url->scheme, &base->scheme);
  }
  if (r->scheme.bytes.len != 0 || r->host.bytes.len != 0 || r->has_user) {
    set_resolved(url, &reference_path, &empty);
  } else if (r->opaque.bytes.len != 0) {
    clear_authority(url);
  } else {
    if (r->path.bytes.len == 0 && !r->force_query && r->raw_query.bytes.len == 0) {
      replace(&url->raw_query, &base->raw_query);
      if (r->fragment.bytes.len == 0) {
        replace(&url->fragment, &base->fragment);
        replace(&url->raw_fragment, &base->raw_fragment);
      }
    }
    if (r->path.bytes.len == 0 && base->opaque.bytes.len != 0) {
      replace(&url->opaque, &base->opaque);
      clear_authority(url);
    } else {
      replace(&url->host, &base->host);
      url->has_user = base->has_user;
      url->password_set = base->password_set;
      replace(&url->username, &base->username);
      replace(&url->password, &base->password);
      MsStrBuild base_path = ms_strbuild_new();
      url_escaped_path(base, &base_path);
      set_resolved(url, &base_path, &reference_path);
      ms_strbuild_free(&base_path);
    }
  }
  ms_strbuild_free(&empty);
  ms_strbuild_free(&reference_path);
}

void url_split_host_port(MsSpan host_port, MsSpan *host, MsSpan *port) {
  MsSpan name = host_port;
  *port = ms_span_of(NULL, 0);
  size_t colon = 0;
  if (url_find_last(host_port, ':', &colon) &&
      url_valid_optional_port(ms_span_of(host_port.ptr + colon, host_port.len - colon))) {
    *port = ms_span_of(host_port.ptr + colon + 1, host_port.len - colon - 1);
    name = ms_span_of(host_port.ptr, colon);
  }
  if (name.len >= 2 && name.ptr[0] == '[' && name.ptr[name.len - 1] == ']') {
    name = ms_span_of(name.ptr + 1, name.len - 2);
  }
  *host = name;
}
