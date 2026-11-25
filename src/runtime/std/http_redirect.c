/* runtime/std/http_redirect.c: what a redirect changes about the next request. */
#include "base/chars.h"
#include "runtime/std/http_client.h"
#include "runtime/std/net_ip.h"

bool ms_http_redirect_method(uint16_t status, MsSpan method, MsString *next, bool *keep_body) {
  if (status >= 301 && status <= 303) {
    *next = ms_string_from_span(ms_span_is_text(method, "HEAD") ? ms_span_of_text("HEAD")
                                                                : ms_span_of_text("GET"));
    *keep_body = false;
    return true;
  }
  if (status == 307 || status == 308) {
    *next = ms_string_from_span(method);
    *keep_body = true;
    return true;
  }
  return false;
}

/* `sub` is `parent` or a subdomain of it; an IP literal matches only itself. */
static bool ms_http_domain_or_subdomain(MsSpan sub, MsSpan parent) {
  if (ms_ascii_equal_fold(sub, parent)) {
    return true;
  }
  MsIp ignored;
  if (ms_ip_parse(sub, &ignored) || ms_ip_parse(parent, &ignored)) {
    return false;
  }
  if (sub.len <= parent.len || sub.ptr[sub.len - parent.len - 1] != '.') {
    return false;
  }
  return ms_ascii_equal_fold(ms_span_of(sub.ptr + (sub.len - parent.len), parent.len), parent);
}

static bool name_is(MsSpan name, const char *text) {
  return ms_ascii_is_text_fold(name, text);
}

static bool describes_body(MsSpan name) {
  return name_is(name, "Content-Type") || name_is(name, "Content-Encoding") ||
         name_is(name, "Content-Language") || name_is(name, "Content-Location");
}

static bool is_credential(MsSpan name) {
  return name_is(name, "Authorization") || name_is(name, "Www-Authenticate") || name_is(name, "Cookie") ||
         name_is(name, "Cookie2");
}

static bool is_origin_credential(MsSpan name) {
  return name_is(name, "Authorization") || name_is(name, "Cookie") || name_is(name, "Proxy-Authorization");
}

MsHeaders *ms_http_redirect_headers(const MsHeaders *hop, const MsHttpUrl *first, const MsHttpUrl *last,
                                    const MsHttpUrl *next, bool keep_body) {
  MsString first_host = ms_http_url_host(first);
  MsString next_host = ms_http_url_host(next);
  const bool subdomain = ms_http_domain_or_subdomain(ms_string_span(&next_host), ms_string_span(&first_host));
  const bool same_origin = ms_http_url_same_origin(next, last);
  MsHeaders *out = ms_headers_new();
  for (size_t g = 0; g < ms_headers_group_count(hop); g++) {
    const MsSpan name = ms_headers_group_name(hop, g);
    const bool dropped = (!keep_body && describes_body(name)) || (is_credential(name) && !subdomain) ||
                         (!same_origin && is_origin_credential(name));
    for (size_t v = 0; !dropped && v < ms_headers_group_size(hop, g); v++) {
      ms_headers_add(out, name, ms_headers_group_value(hop, g, v));
    }
  }
  ms_string_release(&first_host);
  ms_string_release(&next_host);
  return out;
}

bool ms_http_referer_for(const MsHttpUrl *last, const MsHttpUrl *next, const MsHeaders *initial,
                         MsString *out) {
  if (ms_http_url_is_https(last) && !ms_http_url_is_https(next)) {
    return false;
  }
  MsSpan explicit_value;
  if (ms_headers_first(initial, ms_span_of_text("Referer"), &explicit_value) && explicit_value.len > 0) {
    *out = ms_string_from_span(explicit_value);
    return true;
  }
  if (!ms_http_url_same_origin(last, next)) {
    return false;
  }
  *out = ms_http_url_text(last);
  return true;
}
