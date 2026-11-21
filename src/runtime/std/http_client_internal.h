/* What http_client.c and http_exchange.c share: the client record, its connection pool and the response. */
#ifndef MS_RUNTIME_STD_HTTP_CLIENT_INTERNAL_H
#define MS_RUNTIME_STD_HTTP_CLIENT_INTERNAL_H

#include <curl/curl.h>
#include <stdatomic.h>

#include "base/strbuild.h"
#include "runtime/std/compress.h"
#include "runtime/std/http_client.h"
#include "runtime/sys/spin.h"

enum {
  MS_HTTP_DEFAULT_MAX_HEADER_BYTES = 1 << 20,
  MS_HTTP_MAX_FIELDS = 256,
  MS_HTTP_STAGE_HIGH = 256 * 1024, /* staged body bytes at which curl is paused */
  MS_HTTP_SLURP = 2048             /* a redirect's body read so its connection can be reused */
};

/* A pooled connection: the easy handle and the multi handle whose connection cache holds its connections. */
typedef struct HttpConn {
  CURLM *multi;
  CURL *easy;
  int64_t idle_since_ns;
} HttpConn;

struct MsHttpClient {
  atomic_int refs;
  atomic_bool closed;
  MsHttpClientOptions options;
  MsString roots, certificate, key; /* the options' PEM text, owned */
  CURLSH *share;
  MsSpin share_locks[CURL_LOCK_DATA_LAST];
  MsSpin lock;   /* idle and active */
  MsList idle;   /* of HttpConn *, oldest first */
  MsList active; /* of MsHttpResponse * */
};

typedef struct HeadField {
  MsString name;
  MsBytes value;
} HeadField;

struct MsHttpResponse {
  MsHttpClient *client;
  HttpConn *conn; /* NULL once given back */
  struct curl_slist *request_fields;
  MsBytes request_body;
  bool request_head; /* a HEAD request: no body to decode */
  bool add_gzip;     /* the request asked for gzip */
  /* the head */
  uint16_t status;
  MsString protocol;
  MsList fields; /* of HeadField */
  size_t head_bytes;
  size_t max_head_bytes;
  bool head_done;
  MsHeaders *headers;
  MsString url;
  /* the body */
  MsBytes staged;
  size_t staged_pos;
  bool paused;
  bool done;
  bool overflow;
  bool limit;
  uint64_t max;
  uint64_t total;
  MsGunzip *gunzip;
  bool drained; /* the end of the body was reported */
  /* how it ended */
  CURLcode result;
  char error[CURL_ERROR_SIZE];
  const char *abort_text; /* a failure this side raised: static text, or error_text */
  uint8_t abort_status;
  bool has_deadline;
  int64_t deadline_ns;
};

/* http_client.c */
HttpConn *ms_http_conn_take(MsHttpClient *client);
void ms_http_conn_give(MsHttpClient *client, HttpConn *conn, bool reusable);
void ms_http_active_add(MsHttpClient *client, MsHttpResponse *response);
void ms_http_active_remove(MsHttpClient *client, MsHttpResponse *response);

/* http_exchange.c */
typedef struct HttpHop {
  MsSpan method;
  MsSpan url;
  const MsHeaders *headers;
  MsSpan body;
  bool send_body;
} HttpHop;
MsHttpResponse *ms_http_response_new(MsHttpClient *client, const MsHttpRequest *request);
/* Sends one hop and reads its head. OK, or a failure status with text in `*err`. */
uint8_t ms_http_hop_run(MsHttpResponse *response, const HttpHop *hop, MsString *err);
/* Drops a redirect's response, reading a little of its body so the connection can be reused. */
void ms_http_response_discard(MsHttpResponse *response);
/* The value of the first field called `name` in the head just read. */
bool ms_http_head_find(const MsHttpResponse *response, const char *name, MsSpan *value);
/* Builds the delivered headers from the head; INVALID_DATA when they are not text. */
uint8_t ms_http_head_finish(MsHttpResponse *response);
void ms_http_response_free(MsHttpResponse *response);

#endif
