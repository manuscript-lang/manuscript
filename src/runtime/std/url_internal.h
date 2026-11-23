/* What the @std/net/url natives share (url_escape.c, url_parse.c, url_render.c, url.c): the escaping modes,
 * the parsed URL over byte vectors, because text may hold invalid UTF-8 after unescaping, and the operations
 * of Go's net/url that the natives use. Every function that appends takes a builder and leaves earlier text
 * alone. */
#ifndef MS_RUNTIME_STD_URL_INTERNAL_H
#define MS_RUNTIME_STD_URL_INTERNAL_H

#include "base/strbuild.h"

typedef enum UrlEnc {
  URL_ENC_PATH,
  URL_ENC_PATH_SEGMENT,
  URL_ENC_HOST,
  URL_ENC_ZONE,
  URL_ENC_USER_PASSWORD,
  URL_ENC_QUERY_COMPONENT,
  URL_ENC_FRAGMENT
} UrlEnc;

/* A parsed URL (Go's url.URL). Every builder is owned; free with url_parts_free. */
typedef struct UrlParts {
  MsStrBuild scheme;
  MsStrBuild opaque;
  MsStrBuild host;
  MsStrBuild path;
  MsStrBuild raw_path;
  MsStrBuild raw_query;
  MsStrBuild fragment;
  MsStrBuild raw_fragment;
  MsStrBuild username;
  MsStrBuild password;
  bool has_user;
  bool password_set;
  bool omit_host;
  bool force_query;
} UrlParts;

void url_parts_free(UrlParts *parts);
/* A deep copy into the zeroed `out`. */
void url_parts_clone(const UrlParts *source, UrlParts *out);

/* Appends the bytes of `text` to `out`. */
static inline void url_append(MsStrBuild *out, MsSpan text) {
  ms_strbuild_append(out, text);
}
/* Whether the builder's bytes equal `text`. */
static inline bool url_equals(const MsStrBuild *builder, MsSpan text) {
  return ms_span_equal(ms_strbuild_span(builder), text);
}
/* Cuts the builder back to `length` bytes. */
static inline void url_truncate(MsStrBuild *builder, size_t length) {
  builder->bytes.len = length;
}

/* escape.c */
void url_escape(MsSpan text, UrlEnc mode, MsStrBuild *out);
/* False for a malformed escape or a byte the mode forbids; `out` then holds partial text. */
MS_NODISCARD bool url_unescape(MsSpan text, UrlEnc mode, MsStrBuild *out);
bool url_should_escape(uint8_t byte, UrlEnc mode);
bool url_valid_encoded(MsSpan text, UrlEnc mode);
bool url_valid_optional_port(MsSpan port);
bool url_is_canonical(MsSpan text, UrlEnc mode);
/* The index of the last `byte` in `text`, or false. */
bool url_find_last(MsSpan text, uint8_t byte, size_t *at);

/* url_parse.c: Go's url.Parse; false when the text is malformed. */
MS_NODISCARD bool url_parse(MsSpan raw, UrlParts *out);
MS_NODISCARD bool url_set_path(UrlParts *parts, MsSpan path);

/* url_render.c */
void url_escaped_path(const UrlParts *parts, MsStrBuild *out);
void url_render(const UrlParts *parts, MsStrBuild *out);
void url_resolve_reference(const UrlParts *base, const UrlParts *reference, UrlParts *out);
/* Splits "host:port" (the port is empty when there is none) and strips the brackets of an IP literal. */
void url_split_host_port(MsSpan host_port, MsSpan *host, MsSpan *port);

#endif
