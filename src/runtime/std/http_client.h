/* runtime/std/http_client.h: the HTTP client on libcurl (http_url.c: URLs; http_redirect.c: redirect policy;
 * http_client.c: the client and its connection pool; http_exchange.c: one request on the wire and the
 * response body). HTTP/1.1, HTTP/2 over TLS (ALPN), TLS through OpenSSL, optional cookies.
 *
 * Every call that sends or reads blocks the calling thread: run it on the blocking pool, never on the
 * scheduler. A client may be shared by threads; a response belongs to one caller at a time, except that
 * ms_http_client_close may be called from anywhere to cancel what is in flight. Redirects are followed here,
 * not by curl, so the policy matches the language's: no TLS downgrade, no restored credentials after an
 * origin change, a body dropped by 301/302/303. */
#ifndef MS_RUNTIME_STD_HTTP_CLIENT_H
#define MS_RUNTIME_STD_HTTP_CLIENT_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"
#include "runtime/std/http_headers.h"

/* ---- URLs (http_url.c) ---- */

typedef struct MsHttpUrl MsHttpUrl;
/* An absolute http or https URL; NULL when it is neither valid nor of those schemes. */
MsHttpUrl *ms_http_url_parse(MsSpan text);
/* `location` resolved against `base` (RFC 3986), dot segments removed; NULL when invalid or not http(s). */
MsHttpUrl *ms_http_url_resolve(const MsHttpUrl *base, MsSpan location);
void ms_http_url_free(MsHttpUrl *url);
MsString ms_http_url_text(const MsHttpUrl *url);
MsString ms_http_url_host(const MsHttpUrl *url); /* lower case; IPv6 without brackets */
bool ms_http_url_is_https(const MsHttpUrl *url);
/* The same scheme, host and port. */
bool ms_http_url_same_origin(const MsHttpUrl *a, const MsHttpUrl *b);

/* ---- redirect policy (http_redirect.c) ---- */

/* How a response with `status` redirects a request of `method`: 301-303 give GET (HEAD stays HEAD) and drop
 * the body, 307/308 repeat the request and keep it. False for any other status. */
bool ms_http_redirect_method(uint16_t status, MsSpan method, MsString *next, bool *keep_body);
/* `sub` is `parent` or a subdomain of it; an IP literal matches only itself. */
bool ms_http_domain_or_subdomain(MsSpan sub, MsSpan parent);
/* The fields of the request that follows a redirect: those of `hop` less the credentials that must not leave
 * the origin and, when the body is dropped, the fields that describe it. `first` is the request's first URL.
 */
MsHeaders *ms_http_redirect_headers(const MsHeaders *hop, const MsHttpUrl *first, const MsHttpUrl *last,
                                    const MsHttpUrl *next, bool keep_body);
/* The Referer of a redirected request: the caller's own if non-empty; else `last` when it stays on one
 * origin; none (false) when leaving HTTPS for HTTP or crossing origins. */
bool ms_http_referer_for(const MsHttpUrl *last, const MsHttpUrl *next, const MsHeaders *initial,
                         MsString *out);

/* ---- the client (http_client.c) ---- */

typedef struct MsHttpClient MsHttpClient;
typedef struct MsHttpResponse MsHttpResponse;

typedef struct MsHttpClientOptions {
  bool limit_redirects; /* false: no cap; max_redirects 0 returns the redirect itself */
  int64_t max_redirects;
  bool limit_idle; /* idle connections kept; false or 0: uncapped */
  int64_t max_idle;
  int64_t max_header_bytes; /* 0: 1 MiB */
  bool expire_idle;
  int64_t idle_timeout_ns;
  bool decompress; /* decode a single gzip content coding; max_response bounds the decoded size */
  bool cookies;    /* an in-memory jar for the client's lifetime */
  MsSpan roots_pem;
  MsSpan certificate_pem;
  MsSpan private_key_pem;
} MsHttpClientOptions;

typedef struct MsHttpRequest {
  MsSpan method;
  MsSpan url;
  const MsHeaders *headers; /* may be NULL */
  MsSpan body;
  bool limit_response; /* bounds the (decoded) body in bytes */
  int64_t max_response;
  bool has_timeout; /* bounds the whole exchange, body included */
  int64_t timeout_ns;
  /* Called for the request's host and for every redirect target; false refuses. NULL allows all. */
  bool (*host_allowed)(void *context, MsSpan host);
  void *context;
} MsHttpRequest;

/* NULL (with `*err` set) when the options do not describe a usable client. */
MsHttpClient *ms_http_client_new(const MsHttpClientOptions *options, MsString *err);
MsHttpClient *ms_http_client_retain(MsHttpClient *client);
void ms_http_client_release(MsHttpClient *client);
/* Cancels in-flight exchanges, drops idle connections, and refuses later ones with MS_STATUS_CLOSED. */
void ms_http_client_close(MsHttpClient *client);
bool ms_http_client_closed(const MsHttpClient *client);

/* Sends the request and returns once the final response head is read. Status: OK, INVALID_INPUT (method,
 * URL or headers), PERMISSION_DENIED (host), CLOSED, TIMED_OUT, INVALID_DATA (non-text headers) or FAILED
 * with text in `*err`. */
MS_NODISCARD uint8_t ms_http_client_send(MsHttpClient *client, const MsHttpRequest *request,
                                         MsHttpResponse **out, MsString *err);

uint16_t ms_http_response_status(const MsHttpResponse *response);
const MsString *ms_http_response_protocol(const MsHttpResponse *response); /* "HTTP/1.1", "HTTP/2.0" */
const MsHeaders *ms_http_response_headers(const MsHttpResponse *response);
/* The URL the response came from, after redirects. */
const MsString *ms_http_response_url(const MsHttpResponse *response);
/* Appends up to `max` body bytes to `out`; OK with nothing appended is the end of the body. LIMIT_EXCEEDED
 * once the body outgrows the request's bound (the bytes within it are delivered first), TIMED_OUT, CLOSED,
 * INVALID_DATA (bad gzip) or FAILED with text. */
MS_NODISCARD uint8_t ms_http_response_read(MsHttpResponse *response, size_t max, MsBytes *out, MsString *err);
/* Ends the exchange and frees the response; the connection is kept for reuse when the body was read to its
 * end. */
void ms_http_response_close(MsHttpResponse *response);

#endif
