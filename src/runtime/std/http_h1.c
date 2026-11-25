/* runtime/std/http_h1.c: request heads over llhttp and the framing decisions of the server. */
#include "runtime/std/http_h1.h"

#include "llhttp.h"

#include "base/alloc.h"

typedef struct HeadParse {
  MsHeaderField *fields;
  size_t count;
  size_t cap;
  MsSpan target;
  MsSpan pending_name;
  bool too_many;
} HeadParse;

static HeadParse *head_of(llhttp_t *parser) {
  return parser->data;
}

static int on_url(llhttp_t *parser, const char *at, size_t length) {
  HeadParse *head = head_of(parser);
  head->target = ms_span_of((const uint8_t *)at, length);
  return 0;
}

static int on_field_name(llhttp_t *parser, const char *at, size_t length) {
  head_of(parser)->pending_name = ms_span_of((const uint8_t *)at, length);
  return 0;
}

static MsSpan trim_blanks(MsSpan value) {
  while (value.len > 0 && (value.ptr[value.len - 1] == ' ' || value.ptr[value.len - 1] == '\t')) {
    value.len--;
  }
  return value;
}

static int on_field_value(llhttp_t *parser, const char *at, size_t length) {
  HeadParse *head = head_of(parser);
  if (head->count == MS_H1_MAX_FIELDS) {
    head->too_many = true;
    return HPE_USER;
  }
  if (head->count == head->cap) {
    head->cap = head->cap == 0 ? 16 : head->cap * 2;
    head->fields = ms_realloc(head->fields, head->cap * sizeof *head->fields);
  }
  head->fields[head->count++] = (MsHeaderField){
      .name = head->pending_name, .value = trim_blanks(ms_span_of((const uint8_t *)at, length))};
  return 0;
}

static int on_headers_complete(llhttp_t *parser) {
  (void)parser;
  return HPE_PAUSED;
}

/* Whether the request line is `method target HTTP/x`: the only case 505 describes. A line with extra
 * tokens (`GET /a b HTTP/1.1`) is malformed, not a request in some other version. */
static bool names_other_version(MsSpan buf) {
  size_t end = 0;
  while (end < buf.len && buf.ptr[end] != '\r' && buf.ptr[end] != '\n') {
    end++;
  }
  size_t tokens = 0;
  size_t start = 0;
  MsSpan version = {0};
  for (size_t i = 0; i <= end; i++) {
    if (i == end || buf.ptr[i] == ' ') {
      if (tokens == 2) {
        version = ms_span_of(buf.ptr + start, i - start);
      }
      tokens++;
      start = i + 1;
    }
  }
  return tokens == 3 && ms_span_starts_with_text(version, "HTTP/") &&
         !ms_span_is_text(version, "HTTP/1.0") && !ms_span_is_text(version, "HTTP/1.1");
}

static MsH1Bad bad_of(uint16_t status, const char *reason) {
  return (MsH1Bad){.status = status, .reason = reason};
}

static MsH1Parse refuse(MsH1Bad *bad, uint16_t status, const char *reason) {
  *bad = bad_of(status, reason);
  return MS_H1_BAD;
}

static MsH1Parse too_large(MsH1Bad *bad) {
  return refuse(bad, 431, "Request Header Fields Too Large");
}

static MsH1Parse complete(llhttp_t *parser, HeadParse *head, size_t length, MsH1Request *out) {
  *out = (MsH1Request){
      .method = ms_string_from_span(ms_span_of_text(llhttp_method_name(llhttp_get_method(parser)))),
      .target = ms_string_from_span(head->target),
      .minor = llhttp_get_http_minor(parser),
      .fields = ms_headers_from_received(head->fields, head->count),
      .length = length};
  return MS_H1_COMPLETE;
}

/* The outcome of llhttp_execute over a request head. */
static MsH1Parse classify(llhttp_t *parser, enum llhttp_errno error, const uint8_t *base, MsSpan buf,
                          size_t limit, HeadParse *head, MsH1Request *out, MsH1Bad *bad) {
  if (error == HPE_OK) {
    return buf.len > limit ? too_large(bad) : MS_H1_PARTIAL;
  }
  if (head->too_many) {
    return too_large(bad);
  }
  if (error == HPE_PAUSED || error == HPE_PAUSED_UPGRADE) {
    const size_t length = (size_t)((const uint8_t *)llhttp_get_error_pos(parser) - base);
    const uint8_t major = llhttp_get_http_major(parser);
    if (major == 0) {
      return refuse(bad, 400, "Bad Request"); /* a request line without a version */
    }
    if (major != 1 || llhttp_get_http_minor(parser) > 1) {
      return refuse(bad, 505, "HTTP Version Not Supported");
    }
    return length > limit ? too_large(bad) : complete(parser, head, length, out);
  }
  if (error == HPE_INVALID_VERSION && names_other_version(buf)) {
    return refuse(bad, 505, "HTTP Version Not Supported");
  }
  return refuse(bad, 400, "Bad Request");
}

MsH1Parse ms_h1_parse_request(MsSpan buf, size_t limit, MsH1Request *out, MsH1Bad *bad) {
  llhttp_settings_t settings;
  llhttp_settings_init(&settings);
  settings.on_url = on_url;
  settings.on_header_field = on_field_name;
  settings.on_header_value = on_field_value;
  settings.on_headers_complete = on_headers_complete;
  llhttp_t parser;
  llhttp_init(&parser, HTTP_REQUEST, &settings);
  HeadParse head = {0};
  parser.data = &head;
  const enum llhttp_errno error = llhttp_execute(&parser, (const char *)buf.ptr, buf.len);
  const MsH1Parse result = classify(&parser, error, buf.ptr, buf, limit, &head, out, bad);
  ms_free(head.fields);
  return result;
}

void ms_h1_request_release(MsH1Request *request) {
  ms_string_release(&request->method);
  ms_string_release(&request->target);
  ms_headers_free(request->fields);
  request->fields = NULL;
}
