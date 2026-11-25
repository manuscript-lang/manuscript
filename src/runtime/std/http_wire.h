/* runtime/std/http_wire.h: pure HTTP text rules shared by the client and server: request targets
 * (http_target.c) and content-type sniffing (http_sniff.c). */
#ifndef MS_RUNTIME_STD_HTTP_WIRE_H
#define MS_RUNTIME_STD_HTTP_WIRE_H

#include <stdbool.h>

#include "base/safe.h"
#include "base/string.h"

/* A request target split into the routable path and the raw query. */
typedef struct MsHttpTarget {
  MsString path;  /* decoded and cleaned, never above the root; "*" for the asterisk form */
  MsString query; /* raw, without the `?` */
  bool has_host;  /* an absolute-form target */
  MsString host;
} MsHttpTarget;

/* Whether `value` is a Host or :authority value (RFC 9112 section 3.2): a registered name, IPv4 or bracketed
 * IPv6 literal with an optional port. No userinfo, space, path delimiter or non-ASCII byte. Empty is valid.
 */
bool ms_http_valid_authority(MsSpan value);

/* Splits and normalizes the target of a request line. On failure returns false and *reason is the text of the
 * 400 answer (a static string); on success the strings of *out are owned by the caller. */
MS_NODISCARD bool ms_http_target_parse(MsSpan target, MsHttpTarget *out, const char **reason);
void ms_http_target_release(MsHttpTarget *target);

/* http.DetectContentType: the media type of a body whose first 512 bytes are `data`; never null. */
const char *ms_http_detect_content_type(MsSpan data);

#endif
