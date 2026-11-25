/* runtime/std/http_exchange.c: one request through a curl easy handle on the engine thread (http_engine.c),
 * and the response head and body that come back. The engine fills the head and stages the body under the
 * response's lock and wakes the caller; the caller pulls: curl is paused while enough is staged and resumed
 * by the next read. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#include <errno.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/chars.h"
#include "base/ostext.h"
#include "runtime/std/http_client_internal.h"
#include "runtime/std/time_internal.h"

/* ---- the head ---- */

static MsSpan trim_blanks(MsSpan s) {
  while (s.len > 0 && (s.ptr[0] == ' ' || s.ptr[0] == '\t')) {
    s = ms_span_of(s.ptr + 1, s.len - 1);
  }
  while (s.len > 0 && (s.ptr[s.len - 1] == ' ' || s.ptr[s.len - 1] == '\t' || s.ptr[s.len - 1] == '\r' ||
                       s.ptr[s.len - 1] == '\n')) {
    s.len--;
  }
  return s;
}

static void fields_free(MsList *fields) {
  HeadField *items = (HeadField *)(void *)fields->ptr;
  for (size_t i = 0; i < fields->len; i++) {
    ms_string_release(&items[i].name);
    ms_bytes_free(&items[i].value);
  }
  ms_list_free(fields);
}

bool ms_http_head_find(const MsHttpResponse *response, const char *name, MsSpan *value) {
  const HeadField *items = (const HeadField *)(const void *)response->fields.ptr;
  for (size_t i = 0; i < response->fields.len; i++) {
    if (ms_ascii_is_text_fold(ms_string_span(&items[i].name), name)) {
      *value = ms_bytes_span(&items[i].value);
      return true;
    }
  }
  return false;
}

static size_t count_named(const MsHttpResponse *response, const char *name) {
  size_t count = 0;
  const HeadField *items = (const HeadField *)(const void *)response->fields.ptr;
  for (size_t i = 0; i < response->fields.len; i++) {
    count += ms_ascii_is_text_fold(ms_string_span(&items[i].name), name) ? 1u : 0u;
  }
  return count;
}

static void abort_with(MsHttpResponse *response, uint8_t status, const char *text) {
  if (response->abort_text == NULL) {
    response->abort_text = text;
    response->abort_status = status;
  }
}

/* `HTTP/1.1 200 OK`, `HTTP/2 200`: the protocol text and the status. The status is exactly three digits followed by a
 * space or the end of the line; false for anything else, which the caller aborts. */
static bool on_status_line(MsHttpResponse *response, MsSpan line) {
  fields_free(&response->fields);
  response->head_bytes = 0;
  response->head_done = false;
  size_t space = 0;
  while (space < line.len && line.ptr[space] != ' ') {
    space++;
  }
  const MsSpan version = ms_span_of(line.ptr, space);
  ms_string_release(&response->protocol);
  response->protocol =
      ms_string_from_span(ms_span_is_text(version, "HTTP/2") ? ms_span_of_text("HTTP/2.0") : version);
  uint16_t status = 0;
  size_t digits = 0;
  while (space + 1 + digits < line.len && line.ptr[space + 1 + digits] >= '0' && line.ptr[space + 1 + digits] <= '9') {
    digits++;
  }
  const size_t after = space + 1 + digits;
  if (digits != 3 || (after < line.len && line.ptr[after] != ' ')) {
    response->status = 0;
    return false;
  }
  for (size_t i = space + 1; i < after; i++) {
    status = (uint16_t)(status * 10 + (line.ptr[i] - '0'));
  }
  response->status = status;
  return true;
}

/* Whether the body is one gzip coding the request asked for, from the fields just read. */
static bool decodes_gzip(const MsHttpResponse *response) {
  MsSpan coding;
  if (!response->add_gzip || response->request_head ||
      !ms_http_head_find(response, "Content-Encoding", &coding)) {
    return false;
  }
  return count_named(response, "Content-Encoding") == 1 &&
         (ms_ascii_is_text_fold(coding, "gzip") || ms_ascii_is_text_fold(coding, "x-gzip"));
}

/* Whether `value` is a Content-Length: digits only, and a size that fits in 63 bits. */
static bool is_content_length(MsSpan value) {
  if (value.len == 0) {
    return false;
  }
  uint64_t size = 0;
  for (size_t i = 0; i < value.len; i++) {
    if (value.ptr[i] < '0' || value.ptr[i] > '9' || size > (INT64_MAX - (uint64_t)(value.ptr[i] - '0')) / 10) {
      return false;
    }
    size = size * 10 + (uint64_t)(value.ptr[i] - '0');
  }
  return true;
}

/* Whether every Content-Length of the head is valid and they all say the same. */
static bool content_lengths_valid(const MsHttpResponse *response) {
  const HeadField *items = (const HeadField *)(const void *)response->fields.ptr;
  MsSpan first = {0};
  bool seen = false;
  for (size_t i = 0; i < response->fields.len; i++) {
    if (!ms_ascii_is_text_fold(ms_string_span(&items[i].name), "Content-Length")) {
      continue;
    }
    const MsSpan value = ms_bytes_span(&items[i].value);
    if (!is_content_length(value) || (seen && !ms_span_equal(first, value))) {
      return false;
    }
    first = value;
    seen = true;
  }
  return true;
}

static bool on_head_end(MsHttpResponse *response) {
  if (response->status < 200) {
    fields_free(&response->fields);
    return true;
  }
  if (!content_lengths_valid(response)) {
    abort_with(response, MS_STATUS_FAILED, "http: server sent an invalid Content-Length; aborted");
    return false;
  }
  response->head_done = true;
  if (decodes_gzip(response)) {
    response->gunzip = ms_gunzip_new();
  }
  return true;
}

static size_t header_line(MsHttpResponse *response, MsSpan line, size_t whole) {
  if (line.len >= 5 && __builtin_memcmp(line.ptr, "HTTP/", 5) == 0) {
    if (!on_status_line(response, line)) {
      abort_with(response, MS_STATUS_FAILED, "http: server sent an invalid status line; aborted");
      return 0;
    }
    return whole;
  }
  if (response->max_head_bytes != 0 && response->head_bytes > response->max_head_bytes) {
    abort_with(response, MS_STATUS_FAILED, "http: server response headers exceeded the limit; aborted");
    return 0;
  }
  if (line.len == 0) {
    return on_head_end(response) ? whole : 0;
  }
  size_t colon = 0;
  while (colon < line.len && line.ptr[colon] != ':') {
    colon++;
  }
  if (colon == line.len || colon == 0) {
    return whole; /* a folded or malformed line: dropped */
  }
  if (response->fields.len >= MS_HTTP_MAX_FIELDS) {
    abort_with(response, MS_STATUS_FAILED, "http: server response has more than 256 header fields; aborted");
    return 0;
  }
  const HeadField field = {
      .name = ms_string_from_span(ms_span_of(line.ptr, colon)),
      .value = ms_bytes_from_span(trim_blanks(ms_span_of(line.ptr + colon + 1, line.len - colon - 1)))};
  ms_list_push(&response->fields, sizeof field, &field);
  return whole;
}

/* Wakes the caller waiting on this response. The lock is held. */
static void wake(MsHttpResponse *response) {
  if (response->waiter != 0) {
    ms_http_wait_ops()->wake(response->waiter);
  }
}

/* http_exchange.c: curl's callbacks (called on the engine thread). */
static size_t ms_http_on_header(char *buffer, size_t size, size_t count, void *user) {
  MsHttpResponse *response = user;
  const size_t whole = size * count;
  ms_http_mutex_lock(response->lock);
  size_t taken = whole;
  if (!response->head_done) {
    response->head_bytes += whole;
    taken = header_line(response, trim_blanks(ms_span_of((const uint8_t *)buffer, whole)), whole);
    if (response->head_done) {
      wake(response);
    }
  } /* a trailer after the head is dropped */
  ms_http_mutex_unlock(response->lock);
  return taken;
}

uint8_t ms_http_head_finish(MsHttpResponse *response) {
  const bool decoded = response->gunzip != NULL;
  const HeadField *items = (const HeadField *)(const void *)response->fields.ptr;
  MsList spans = {0};
  for (size_t i = 0; i < response->fields.len; i++) {
    const MsSpan name = ms_string_span(&items[i].name);
    if (decoded &&
        (ms_ascii_is_text_fold(name, "Content-Encoding") || ms_ascii_is_text_fold(name, "Content-Length"))) {
      continue;
    }
    const MsHeaderField field = {.name = name, .value = ms_bytes_span(&items[i].value)};
    ms_list_push(&spans, sizeof field, &field);
  }
  response->headers = ms_headers_from_received((const MsHeaderField *)(const void *)spans.ptr, spans.len);
  ms_list_free(&spans);
  if (!ms_headers_is_text(response->headers)) {
    return MS_STATUS_INVALID_DATA;
  }
  return MS_STATUS_OK;
}

/* ---- the body ---- */

/* Adds body bytes to the staging buffer within the request's bound; false once the bound is crossed. */
static bool stage(MsHttpResponse *response, MsSpan bytes) {
  size_t take = bytes.len;
  if (response->limit && take > response->max - response->total) {
    take = (size_t)(response->max - response->total);
    response->overflow = true;
  }
  if (take > 0) {
    __builtin_memcpy(ms_list_extend(&response->staged, 1, take), bytes.ptr, take);
    response->total += take;
  }
  return !response->overflow;
}

/* Inflates `in` into the staging buffer. */
static bool stage_gunzip(MsHttpResponse *response, MsSpan in) {
  uint8_t out[16384];
  size_t used = 0;
  for (;;) {
    size_t consumed = 0;
    size_t produced = 0;
    const uint8_t status = ms_gunzip_step(response->gunzip, in.ptr + used, in.len - used, true, out,
                                          sizeof out, &consumed, &produced);
    used += consumed;
    if (status == MS_GUNZIP_INVALID) {
      abort_with(response, MS_STATUS_INVALID_DATA, "gzip: invalid compressed data");
      return false;
    }
    if (produced > 0 && !stage(response, ms_span_of(out, produced))) {
      return false;
    }
    if (status == MS_GUNZIP_DONE || (used == in.len && produced < sizeof out)) {
      return true;
    }
  }
}

static size_t ms_http_on_body(char *buffer, size_t size, size_t count, void *user) {
  MsHttpResponse *response = user;
  const size_t whole = size * count;
  const MsSpan bytes = ms_span_of((const uint8_t *)buffer, whole);
  ms_http_mutex_lock(response->lock);
  size_t taken = whole;
  if (response->discarding) {
    response->discarded += whole;
    taken = response->discarded > MS_HTTP_SLURP ? 0 : whole; /* a long body is not worth reading */
  } else if (response->staged.len - response->staged_pos >= MS_HTTP_STAGE_HIGH) {
    response->paused = true;
    taken = CURL_WRITEFUNC_PAUSE;
  } else {
    const bool kept = response->gunzip != NULL ? stage_gunzip(response, bytes) : stage(response, bytes);
    taken = kept ? whole : 0;
    wake(response);
  }
  ms_http_mutex_unlock(response->lock);
  return taken;
}

/* The OS error text, lower-case first letter, as the language words transport failures. */
static MsString os_text(long error_number) {
  MsStrBuild text = ms_strbuild_new();
  ms_os_error_text((int)error_number, &text);
  MsString out = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
  MsSpan span = ms_string_span(&out);
  MsStrBuild lower = ms_strbuild_new();
  ms_strbuild_append_byte(&lower, span.len > 0 ? ms_ascii_to_lower(span.ptr[0]) : 0);
  if (span.len > 1) {
    ms_strbuild_append(&lower, ms_span_of(span.ptr + 1, span.len - 1));
  }
  ms_string_release(&out);
  out = ms_strbuild_finish(&lower);
  ms_strbuild_free(&lower);
  return out;
}

static MsString static_text(const char *text) {
  return ms_string_from_span(ms_span_of_text(text));
}

static MsString unresolved_text(const MsHttpResponse *response) {
  MsHttpUrl *url = ms_http_url_parse(ms_string_span(&response->url));
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot resolve host \"");
  if (url != NULL) {
    MsString host = ms_http_url_host(url);
    ms_strbuild_append_string(&text, &host);
    ms_string_release(&host);
    ms_http_url_free(url);
  }
  ms_strbuild_append_text(&text, "\"");
  MsString out = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
  return out;
}

/* The text of a transport failure, in the words the language uses for it. */
static MsString failure_text(MsHttpResponse *response) {
  const long error_number = response->os_errno;
  switch (response->result) {
  case CURLE_COULDNT_RESOLVE_HOST:
    return unresolved_text(response);
  case CURLE_COULDNT_CONNECT:
    return error_number == ECONNREFUSED || error_number == 0 ? static_text("connection refused")
                                                             : os_text(error_number);
  case CURLE_GOT_NOTHING:
  case CURLE_PARTIAL_FILE:
    return static_text("connection closed before the exchange completed");
  case CURLE_SEND_ERROR:
  case CURLE_RECV_ERROR:
    return error_number == ECONNRESET
               ? static_text("connection reset by peer")
               : static_text(response->error[0] != '\0' ? response->error
                                                        : curl_easy_strerror(response->result));
  default:
    return static_text(response->error[0] != '\0' ? response->error : curl_easy_strerror(response->result));
  }
}

/* The status and text of how the exchange ended; OK when it ended well. */
static uint8_t outcome(MsHttpResponse *response, MsString *err) {
  if (response->abort_text != NULL) {
    *err = static_text(response->abort_text);
    return response->abort_status;
  }
  if (atomic_load(&response->client->closed)) {
    return MS_STATUS_CLOSED;
  }
  if (response->result == CURLE_OK) {
    return MS_STATUS_OK;
  }
  if (response->result == CURLE_OPERATION_TIMEDOUT) {
    return MS_STATUS_TIMED_OUT;
  }
  *err = failure_text(response);
  return MS_STATUS_FAILED;
}

/* ---- one hop ---- */

static void add_field(MsHttpResponse *response, MsSpan name, MsSpan value) {
  MsStrBuild line = ms_strbuild_new();
  ms_strbuild_append(&line, name);
  ms_strbuild_append_text(&line, value.len == 0 ? ";" : ": ");
  ms_strbuild_append(&line, trim_blanks(value));
  MsString text = ms_strbuild_finish(&line);
  ms_strbuild_free(&line);
  char *copy = ms_alloc_zeroed(ms_string_length(&text) + 1);
  __builtin_memcpy(copy, ms_string_span(&text).ptr, ms_string_length(&text));
  response->request_fields = curl_slist_append(response->request_fields, copy);
  ms_free(copy);
  ms_string_release(&text);
}

typedef struct Seen {
  bool agent;
  bool type;
  bool encoding;
} Seen;

static void add_fields(MsHttpResponse *response, const HttpHop *hop, Seen *seen) {
  for (size_t g = 0; hop->headers != NULL && g < ms_headers_group_count(hop->headers); g++) {
    const MsSpan name = ms_headers_group_name(hop->headers, g);
    seen->agent = seen->agent || ms_ascii_is_text_fold(name, "User-Agent");
    seen->type = seen->type || ms_ascii_is_text_fold(name, "Content-Type");
    seen->encoding = seen->encoding || ms_ascii_is_text_fold(name, "Accept-Encoding");
    for (size_t v = 0; v < ms_headers_group_size(hop->headers, g); v++) {
      add_field(response, name, ms_headers_group_value(hop->headers, g, v));
    }
  }
}

static bool wants_body(const HttpHop *hop) {
  return hop->send_body && (hop->body.len > 0 || ms_span_is_text(hop->method, "POST") ||
                            ms_span_is_text(hop->method, "PUT") || ms_span_is_text(hop->method, "PATCH"));
}

static void set_method(MsHttpResponse *response, CURL *easy, const HttpHop *hop, char **method) {
  *method = ms_alloc_zeroed(hop->method.len + 1);
  __builtin_memcpy(*method, hop->method.ptr, hop->method.len);
  response->request_head = ms_span_is_text(hop->method, "HEAD");
  if (response->request_head) {
    curl_easy_setopt(easy, CURLOPT_NOBODY, 1L);
  } else if (wants_body(hop)) {
    response->request_body = ms_bytes_from_span(hop->body);
    curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)response->request_body.len);
    curl_easy_setopt(easy, CURLOPT_POSTFIELDS, response->request_body.ptr);
    curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, *method);
  } else if (ms_span_is_text(hop->method, "GET")) {
    curl_easy_setopt(easy, CURLOPT_HTTPGET, 1L);
  } else {
    curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, *method);
  }
}

static void set_tls(const MsHttpClient *client, CURL *easy) {
  const MsHttpClientOptions *o = &client->options;
  if (o->roots_pem.len > 0) {
    const struct curl_blob roots = {(void *)(uintptr_t)o->roots_pem.ptr, o->roots_pem.len, CURL_BLOB_COPY};
    curl_easy_setopt(easy, CURLOPT_CAINFO_BLOB, &roots);
  }
#ifdef _WIN32
  else {
    /* No bundled roots on Windows: trust the system store, as OpenSSL elsewhere trusts its default path. */
    curl_easy_setopt(easy, CURLOPT_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA);
  }
#endif
  if (o->certificate_pem.len > 0) {
    const struct curl_blob cert = {(void *)(uintptr_t)o->certificate_pem.ptr, o->certificate_pem.len,
                                   CURL_BLOB_COPY};
    const struct curl_blob key = {(void *)(uintptr_t)o->private_key_pem.ptr, o->private_key_pem.len,
                                  CURL_BLOB_COPY};
    curl_easy_setopt(easy, CURLOPT_SSLCERT_BLOB, &cert);
    curl_easy_setopt(easy, CURLOPT_SSLCERTTYPE, "PEM");
    curl_easy_setopt(easy, CURLOPT_SSLKEY_BLOB, &key);
    curl_easy_setopt(easy, CURLOPT_SSLKEYTYPE, "PEM");
  }
}

/* Before a request is sent: the address the connection reached must be allowed. */
static int on_connected(void *data, char *remote, char *local, int remote_port, int local_port) {
  (void)local;
  (void)local_port;
  const MsHttpResponse *response = data;
  union {
    struct sockaddr_in v4;
    struct sockaddr_in6 v6;
  } address;
  const bool known = uv_ip4_addr(remote, remote_port, &address.v4) == 0 ||
                     uv_ip6_addr(remote, remote_port, &address.v6) == 0;
  return known && response->address_allowed(response->context, &address) ? CURL_PREREQFUNC_OK
                                                                         : CURL_PREREQFUNC_ABORT;
}

static void configure(MsHttpResponse *response, const HttpHop *hop) {
  CURL *easy = response->easy;
  char *url = ms_alloc_zeroed(hop->url.len + 1);
  __builtin_memcpy(url, hop->url.ptr, hop->url.len);
  curl_easy_setopt(easy, CURLOPT_URL, url);
  curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(easy, CURLOPT_PATH_AS_IS, 1L); /* the server decides what `..` and `%2F` in a path mean */
  curl_easy_setopt(easy, CURLOPT_PROXY, "");
  curl_easy_setopt(easy, CURLOPT_PROTOCOLS_STR, "http,https");
  curl_easy_setopt(easy, CURLOPT_HTTP_CONTENT_DECODING, 0L);
  curl_easy_setopt(easy, CURLOPT_TCP_KEEPALIVE, 1L);
  curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, ms_http_on_header);
  curl_easy_setopt(easy, CURLOPT_HEADERDATA, response);
  curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, ms_http_on_body);
  curl_easy_setopt(easy, CURLOPT_WRITEDATA, response);
  curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, response->error);
  curl_easy_setopt(easy, CURLOPT_SHARE, response->client->share);
  curl_easy_setopt(easy, CURLOPT_PRIVATE, response);
  if (response->address_allowed != NULL) {
    curl_easy_setopt(easy, CURLOPT_PREREQFUNCTION, on_connected);
    curl_easy_setopt(easy, CURLOPT_PREREQDATA, response);
  }
  if (response->client->options.expire_idle) {
    curl_easy_setopt(easy, CURLOPT_MAXAGE_CONN,
                     (long)((response->client->options.idle_timeout_ns + 999999999) / 1000000000));
  }
  if (response->client->options.cookies) {
    curl_easy_setopt(easy, CURLOPT_COOKIEFILE, "");
  }
  if (response->has_deadline) {
    const int64_t left = (response->deadline_ns - ms_clock_monotonic_since_start()) / 1000000;
    curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, (long)(left < 1 ? 1 : left));
  }
  set_tls(response->client, easy);
  char *method = NULL;
  set_method(response, easy, hop, &method);
  Seen seen = {0};
  add_fields(response, hop, &seen);
  response->add_gzip = response->client->options.decompress && !seen.encoding;
  if (response->add_gzip) {
    response->request_fields = curl_slist_append(response->request_fields, "Accept-Encoding: gzip");
  }
  if (!seen.agent) {
    curl_easy_setopt(easy, CURLOPT_USERAGENT, "ms-http");
  }
  response->request_fields = curl_slist_append(response->request_fields, "Accept:");
  response->request_fields = curl_slist_append(response->request_fields, "Expect:");
  if (wants_body(hop) && !seen.type) {
    response->request_fields = curl_slist_append(response->request_fields, "Content-Type:");
  }
  curl_easy_setopt(easy, CURLOPT_HTTPHEADER, response->request_fields);
  /* curl copies the strings it was given (URL and method) when the handle is configured. */
  ms_free(url);
  ms_free(method);
}

/* ---- creating, starting and finishing ---- */

MsHttpResponse *ms_http_response_new(MsHttpClient *client, const MsHttpRequest *request) {
  MsHttpResponse *response = ms_alloc_zeroed(sizeof *response);
  atomic_init(&response->refs, 1);
  response->client = ms_http_client_retain(client);
  response->easy = curl_easy_init();
  response->lock = ms_http_mutex_new();
  response->max_head_bytes = client->options.max_header_bytes != 0 ? (size_t)client->options.max_header_bytes
                                                                   : (size_t)MS_HTTP_DEFAULT_MAX_HEADER_BYTES;
  response->limit = request->limit_response;
  response->max = request->limit_response ? (uint64_t)request->max_response : 0;
  response->has_deadline = request->has_timeout;
  response->address_allowed = request->address_allowed;
  response->context = request->context;
  if (request->has_timeout) {
    response->deadline_ns = ms_clock_monotonic_since_start() + request->timeout_ns;
  }
  response->protocol = ms_string_empty();
  response->url = ms_string_empty();
  return response;
}

void ms_http_response_unref(MsHttpResponse *response) {
  if (atomic_fetch_sub(&response->refs, 1) != 1) {
    return;
  }
  curl_easy_cleanup(response->easy);
  curl_slist_free_all(response->request_fields);
  ms_bytes_free(&response->request_body);
  fields_free(&response->fields);
  if (response->headers != NULL) {
    ms_headers_free(response->headers);
  }
  ms_bytes_free(&response->staged);
  ms_gunzip_free(response->gunzip);
  ms_string_release(&response->protocol);
  ms_string_release(&response->url);
  ms_http_mutex_free(response->lock);
  ms_http_client_release(response->client);
  ms_free(response);
}

/* Finishes the gzip stream at the end of the body; false (with the failure noted) when it was cut or corrupt.
 * The lock is held. */
static bool end_gunzip(MsHttpResponse *response) {
  uint8_t out[4096];
  for (;;) {
    size_t consumed = 0;
    size_t produced = 0;
    const uint8_t status =
        ms_gunzip_step(response->gunzip, NULL, 0, false, out, sizeof out, &consumed, &produced);
    if (produced > 0 && !stage(response, ms_span_of(out, produced))) {
      return true;
    }
    if (status == MS_GUNZIP_DONE) {
      return true;
    }
    if (status != MS_GUNZIP_OK) {
      abort_with(response, MS_STATUS_INVALID_DATA, "gzip: unexpected end of compressed data");
      return false;
    }
  }
}

void ms_http_response_finished(MsHttpResponse *response, CURLcode result) {
  long error_number = 0;
  (void)curl_easy_getinfo(response->easy, CURLINFO_OS_ERRNO, &error_number);
  ms_http_mutex_lock(response->lock);
  response->os_errno = error_number;
  response->result = result;
  if (result == CURLE_OK && response->gunzip != NULL && !response->overflow) {
    (void)end_gunzip(response);
  }
  response->done = true;
  wake(response);
  ms_http_mutex_unlock(response->lock);
}

/* Waits for a change of the response; the lock is held on entry and on return. */
static MsHttpWake wait_change(MsHttpResponse *response) {
  const MsHttpWaitOps *ops = ms_http_wait_ops();
  const uint64_t waiter = ops->begin();
  response->waiter = waiter;
  ms_http_mutex_unlock(response->lock);
  const MsHttpWake woke = ops->wait(waiter, -1);
  ms_http_mutex_lock(response->lock);
  response->waiter = 0;
  ops->end(waiter);
  return woke;
}

/* The caller was cancelled while waiting: ends the transfer. */
static uint8_t cancelled(MsHttpResponse *response) {
  ms_http_mutex_unlock(response->lock);
  ms_http_engine_cancel(response);
  return MS_STATUS_CLOSED;
}

uint8_t ms_http_hop_run(MsHttpResponse *response, const HttpHop *hop, MsString *err) {
  configure(response, hop);
  ms_string_release(&response->url);
  response->url = ms_string_from_span(hop->url);
  ms_http_engine_start(response);
  ms_http_mutex_lock(response->lock);
  while (!response->head_done && !response->done) {
    if (wait_change(response) == MS_HTTP_WAIT_CANCELLED) {
      return cancelled(response);
    }
  }
  const bool ready = response->head_done;
  const uint8_t status = ready ? MS_STATUS_OK : outcome(response, err);
  ms_http_mutex_unlock(response->lock);
  return status == MS_STATUS_OK && !ready ? MS_STATUS_FAILED : status;
}

/* ---- reading the body ---- */

static uint8_t read_end(MsHttpResponse *response, MsString *err) {
  if (response->overflow) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  const uint8_t status = outcome(response, err);
  response->drained = status == MS_STATUS_OK;
  return status;
}

uint8_t ms_http_response_read(MsHttpResponse *response, size_t max, MsBytes *out, MsString *err) {
  if (max == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  ms_http_mutex_lock(response->lock);
  for (;;) {
    const size_t available = response->staged.len - response->staged_pos;
    if (available > 0) {
      const size_t take = available < max ? available : max;
      __builtin_memcpy(ms_list_extend(out, 1, take), response->staged.ptr + response->staged_pos, take);
      response->staged_pos += take;
      if (response->staged_pos == response->staged.len) {
        response->staged.len = 0;
        response->staged_pos = 0;
      }
      const bool resume =
          response->paused && response->staged.len - response->staged_pos < MS_HTTP_STAGE_HIGH / 2;
      response->paused = response->paused && !resume;
      ms_http_mutex_unlock(response->lock);
      if (resume) {
        ms_http_engine_resume(response);
      }
      return MS_STATUS_OK;
    }
    if (response->done) {
      const uint8_t status = read_end(response, err);
      ms_http_mutex_unlock(response->lock);
      return status;
    }
    if (wait_change(response) == MS_HTTP_WAIT_CANCELLED) {
      return cancelled(response);
    }
  }
}

void ms_http_response_discard(MsHttpResponse *response) {
  ms_http_mutex_lock(response->lock);
  response->discarding = true;
  const bool resume = response->paused;
  response->paused = false;
  response->staged.len = 0;
  response->staged_pos = 0;
  ms_http_mutex_unlock(response->lock);
  if (resume) {
    ms_http_engine_resume(response);
  }
  ms_http_response_unref(response); /* the engine finishes the transfer and frees the record */
}

void ms_http_response_close(MsHttpResponse *response) {
  if (response == NULL) {
    return;
  }
  ms_http_mutex_lock(response->lock);
  const bool running = !response->done;
  ms_http_mutex_unlock(response->lock);
  if (running) {
    ms_http_engine_cancel_and_wait(response);
  }
  ms_http_response_unref(response);
}

uint16_t ms_http_response_status(const MsHttpResponse *response) {
  return response->status;
}

const MsString *ms_http_response_protocol(const MsHttpResponse *response) {
  return &response->protocol;
}

const MsHeaders *ms_http_response_headers(const MsHttpResponse *response) {
  return response->headers;
}
