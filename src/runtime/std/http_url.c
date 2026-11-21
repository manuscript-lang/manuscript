/* runtime/std/http_url.c: absolute http and https URLs and relative resolution, on curl's URL parser. */
#include <curl/curl.h>

#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/std/http_client.h"

struct MsHttpUrl {
  CURLU *handle;
};

static MsHttpUrl *wrap(CURLU *handle) {
  if (handle == NULL) {
    return NULL;
  }
  char *scheme = NULL;
  const CURLUcode got = curl_url_get(handle, CURLUPART_SCHEME, &scheme, 0);
  const MsSpan name = got == CURLUE_OK ? ms_span_of_text(scheme) : ms_span_of_text("");
  const bool web = ms_span_is_text(name, "http") || ms_span_is_text(name, "https");
  curl_free(scheme);
  if (!web) {
    curl_url_cleanup(handle);
    return NULL;
  }
  MsHttpUrl *url = ms_alloc_zeroed(sizeof *url);
  url->handle = handle;
  return url;
}

/* `text` as the NUL-terminated string curl wants. */
static char *terminated(MsSpan text) {
  char *copy = ms_alloc_zeroed(text.len + 1);
  __builtin_memcpy(copy, text.ptr, text.len);
  return copy;
}

static bool has_nul(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == 0) {
      return true;
    }
  }
  return false;
}

MsHttpUrl *ms_http_url_parse(MsSpan text) {
  if (text.len == 0 || has_nul(text)) {
    return NULL;
  }
  CURLU *handle = curl_url();
  char *copy = terminated(text);
  const CURLUcode set = curl_url_set(handle, CURLUPART_URL, copy, 0);
  ms_free(copy);
  if (set != CURLUE_OK) {
    curl_url_cleanup(handle);
    return NULL;
  }
  return wrap(handle);
}

MsHttpUrl *ms_http_url_resolve(const MsHttpUrl *base, MsSpan location) {
  if (has_nul(location)) {
    return NULL;
  }
  CURLU *handle = curl_url_dup(base->handle);
  char *copy = terminated(location);
  const CURLUcode set = curl_url_set(handle, CURLUPART_URL, copy, 0);
  ms_free(copy);
  if (set != CURLUE_OK) {
    curl_url_cleanup(handle);
    return NULL;
  }
  return wrap(handle);
}

void ms_http_url_free(MsHttpUrl *url) {
  if (url == NULL) {
    return;
  }
  curl_url_cleanup(url->handle);
  ms_free(url);
}

static MsString part(const MsHttpUrl *url, CURLUPart which, unsigned flags) {
  char *text = NULL;
  if (curl_url_get(url->handle, which, &text, flags) != CURLUE_OK) {
    return ms_string_empty();
  }
  const MsString out = ms_string_from_span(ms_span_of_text(text));
  curl_free(text);
  return out;
}

MsString ms_http_url_text(const MsHttpUrl *url) {
  return part(url, CURLUPART_URL, 0);
}

MsString ms_http_url_host(const MsHttpUrl *url) {
  MsString host = part(url, CURLUPART_HOST, 0);
  MsSpan span = ms_string_span(&host);
  if (span.len >= 2 && span.ptr[0] == '[' && span.ptr[span.len - 1] == ']') {
    const MsString inner = ms_string_from_span(ms_span_of(span.ptr + 1, span.len - 2));
    ms_string_release(&host);
    host = inner;
    span = ms_string_span(&host);
  }
  MsStrBuild lower = ms_strbuild_new();
  for (size_t i = 0; i < span.len; i++) {
    ms_strbuild_append_byte(&lower, ms_ascii_to_lower(span.ptr[i]));
  }
  ms_string_release(&host);
  const MsString out = ms_strbuild_finish(&lower);
  ms_strbuild_free(&lower);
  return out;
}

bool ms_http_url_is_https(const MsHttpUrl *url) {
  MsString scheme = part(url, CURLUPART_SCHEME, 0);
  const bool https = ms_span_is_text(ms_string_span(&scheme), "https");
  ms_string_release(&scheme);
  return https;
}

bool ms_http_url_same_origin(const MsHttpUrl *a, const MsHttpUrl *b) {
  MsString scheme_a = part(a, CURLUPART_SCHEME, 0);
  MsString scheme_b = part(b, CURLUPART_SCHEME, 0);
  MsString host_a = ms_http_url_host(a);
  MsString host_b = ms_http_url_host(b);
  MsString port_a = part(a, CURLUPART_PORT, CURLU_DEFAULT_PORT);
  MsString port_b = part(b, CURLUPART_PORT, CURLU_DEFAULT_PORT);
  const bool same = ms_span_equal(ms_string_span(&scheme_a), ms_string_span(&scheme_b)) &&
                    ms_span_equal(ms_string_span(&host_a), ms_string_span(&host_b)) &&
                    ms_span_equal(ms_string_span(&port_a), ms_string_span(&port_b));
  MsString *all[] = {&scheme_a, &scheme_b, &host_a, &host_b, &port_a, &port_b};
  for (size_t i = 0; i < 6; i++) {
    ms_string_release(all[i]);
  }
  return same;
}
