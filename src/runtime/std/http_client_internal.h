/* What the HTTP client's files share: the client and response records, and the engine they run on.
 *
 * Threads. Callers (tasks or plain threads) build requests and read responses; one engine thread
 * (http_engine.c) owns every curl multi handle and runs them from a libuv loop. A response's mutex guards
 * what both sides touch; the caller waits through the waiter hooks of http_sync.h and the engine wakes it. */
#ifndef MS_RUNTIME_STD_HTTP_CLIENT_INTERNAL_H
#define MS_RUNTIME_STD_HTTP_CLIENT_INTERNAL_H

#include <curl/curl.h>
#include <stdatomic.h>

#include "base/strbuild.h"
#include "runtime/std/compress.h"
#include "runtime/std/http_client.h"
#include "runtime/std/http_sync.h"

enum {
  MS_HTTP_DEFAULT_MAX_HEADER_BYTES = 1 << 20,
  MS_HTTP_MAX_FIELDS = 256,
  MS_HTTP_STAGE_HIGH = 256 * 1024, /* staged body bytes at which curl is paused */
  MS_HTTP_SLURP = 2048             /* a redirect's body read so its connection can be reused */
};

struct MsHttpClient {
  atomic_int refs;
  atomic_bool closed;
  MsHttpClientOptions options;
  MsString roots, certificate, key; /* the options' PEM text, owned */
  CURLM *multi;
  CURLSH *share;
  MsHttpMutex *share_locks[CURL_LOCK_DATA_LAST];
  void *timer;   /* the engine's timer for the multi; engine thread only */
  MsList active; /* of MsHttpResponse *; engine thread only */
};

typedef struct HeadField {
  MsString name;
  MsBytes value;
} HeadField;

struct MsHttpResponse {
  atomic_int refs;
  MsHttpClient *client;
  CURL *easy;
  struct curl_slist *request_fields;
  MsBytes request_body;
  bool request_head; /* a HEAD request: no body to decode */
  bool add_gzip;     /* the request asked for gzip */
  bool has_deadline;
  int64_t deadline_ns;
  size_t max_head_bytes;
  bool limit;
  uint64_t max;
  MsString url;
  /* guarded by `lock`: */
  MsHttpMutex *lock;
  uint64_t waiter; /* a caller waiting for a change; 0 for none */
  uint16_t status;
  MsString protocol;
  MsList fields; /* of HeadField */
  size_t head_bytes;
  bool head_done;
  MsBytes staged;
  size_t staged_pos;
  bool paused;
  bool done;
  bool overflow;
  uint64_t total;
  MsGunzip *gunzip;
  bool discarding;
  size_t discarded;
  CURLcode result;
  char error[CURL_ERROR_SIZE];
  const char *abort_text; /* a failure raised on this side: static text */
  uint8_t abort_status;
  long os_errno;
  /* caller side only: */
  MsHeaders *headers;
  bool drained; /* the end of the body was reported */
};

/* http_engine.c: commands for the engine thread. */
void ms_http_engine_start(MsHttpResponse *response);    /* adds the response's easy handle */
void ms_http_engine_resume(MsHttpResponse *response);   /* continues a paused transfer */
void ms_http_engine_cancel(MsHttpResponse *response);   /* ends an unfinished transfer */
void ms_http_engine_close_client(MsHttpClient *client); /* ends every transfer of the client */
void ms_http_engine_free_client(
    MsHttpClient *client); /* destroys the client's multi handle, then the record */
/* Called by the engine as a transfer ends (also from cancel): marks it done and wakes the waiter. */
void ms_http_response_finished(MsHttpResponse *response, CURLcode result);

/* http_exchange.c: curl's callbacks (called on the engine thread). */
size_t ms_http_on_header(char *buffer, size_t size, size_t count, void *user);
size_t ms_http_on_body(char *buffer, size_t size, size_t count, void *user);

typedef struct HttpHop {
  MsSpan method;
  MsSpan url;
  const MsHeaders *headers;
  MsSpan body;
  bool send_body;
} HttpHop;
MsHttpResponse *ms_http_response_new(MsHttpClient *client, const MsHttpRequest *request);
/* Sends one hop and waits for its head. OK, or a failure status with text in `*err`. */
uint8_t ms_http_hop_run(MsHttpResponse *response, const HttpHop *hop, MsString *err);
/* Drops a redirect's response; what is left of its body is read in the background so the connection is
 * reused. */
void ms_http_response_discard(MsHttpResponse *response);
/* The value of the first field called `name` in the head just read. */
bool ms_http_head_find(const MsHttpResponse *response, const char *name, MsSpan *value);
/* Builds the delivered headers from the head; INVALID_DATA when they are not text. */
uint8_t ms_http_head_finish(MsHttpResponse *response);
void ms_http_response_unref(MsHttpResponse *response);

#endif
