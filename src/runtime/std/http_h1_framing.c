/* runtime/std/http_h1_framing.c: what a request head's fields say about its body and its connection. */
#include "runtime/std/http_h1.h"

static bool ci_equal(MsSpan a, const char *text) {
  const MsSpan b = ms_span_of_text(text);
  if (a.len != b.len) {
    return false;
  }
  for (size_t i = 0; i < a.len; i++) {
    const uint8_t c = a.ptr[i];
    const uint8_t d = b.ptr[i];
    if ((uint8_t)(c >= 'A' && c <= 'Z' ? c + 32 : c) != (uint8_t)(d >= 'A' && d <= 'Z' ? d + 32 : d)) {
      return false;
    }
  }
  return true;
}

static MsSpan trim_ascii(MsSpan s) {
  while (s.len > 0 && (s.ptr[0] == ' ' || s.ptr[0] == '\t')) {
    s = ms_span_of(s.ptr + 1, s.len - 1);
  }
  while (s.len > 0 && (s.ptr[s.len - 1] == ' ' || s.ptr[s.len - 1] == '\t')) {
    s.len--;
  }
  return s;
}

/* Calls `each` with every comma-separated, blank-trimmed token of `value` (empty ones included) until it
 * returns false. */
typedef bool (*TokenFn)(void *state, MsSpan token);

static bool for_each_token(MsSpan value, TokenFn each, void *state) {
  size_t start = 0;
  for (size_t i = 0; i <= value.len; i++) {
    if (i == value.len || value.ptr[i] == ',') {
      if (!each(state, trim_ascii(ms_span_of(value.ptr + start, i - start)))) {
        return false;
      }
      start = i + 1;
    }
  }
  return true;
}

typedef struct TokenQuery {
  const char *token;
  bool found;
} TokenQuery;

static bool match_token(void *state, MsSpan token) {
  TokenQuery *query = state;
  query->found = query->found || ci_equal(token, query->token);
  return !query->found;
}

static bool value_has_token(MsSpan value, const char *token) {
  TokenQuery query = {.token = token};
  (void)for_each_token(value, match_token, &query);
  return query.found;
}

/* The group of `name`, or false. */
static bool find_group(const MsHeaders *fields, const char *name, size_t *group) {
  for (size_t g = 0; g < ms_headers_group_count(fields); g++) {
    if (ci_equal(ms_headers_group_name(fields, g), name)) {
      *group = g;
      return true;
    }
  }
  return false;
}

bool ms_h1_has_token(const MsHeaders *fields, const char *name, const char *token) {
  size_t group = 0;
  if (!find_group(fields, name, &group)) {
    return false;
  }
  for (size_t v = 0; v < ms_headers_group_size(fields, group); v++) {
    if (value_has_token(ms_headers_group_value(fields, group, v), token)) {
      return true;
    }
  }
  return false;
}

bool ms_h1_keep_alive(uint8_t minor, const MsHeaders *fields) {
  if (ms_h1_has_token(fields, "Connection", "close")) {
    return false;
  }
  return minor >= 1 || ms_h1_has_token(fields, "Connection", "keep-alive");
}

typedef struct ConnectionFlags {
  bool close;
  bool keep_alive;
} ConnectionFlags;

static bool note_connection(void *state, MsSpan token) {
  ConnectionFlags *flags = state;
  flags->close = flags->close || ci_equal(token, "close");
  flags->keep_alive = flags->keep_alive || ci_equal(token, "keep-alive");
  return true;
}

static void scan_group(const MsHeaders *fields, size_t group, MsH1Scan *scan) {
  const MsSpan name = ms_headers_group_name(fields, group);
  const size_t size = ms_headers_group_size(fields, group);
  if (ci_equal(name, "Host")) {
    scan->hosts += size;
    scan->host = ms_headers_group_value(fields, group, size - 1);
  } else if (ci_equal(name, "Content-Length")) {
    scan->content_length = true;
  } else if (ci_equal(name, "Transfer-Encoding")) {
    scan->transfer_encoding = true;
  }
  for (size_t v = 0; v < size; v++) {
    const MsSpan value = ms_headers_group_value(fields, group, v);
    if (ci_equal(name, "Expect")) {
      scan->expect_continue = scan->expect_continue || value_has_token(value, "100-continue");
    } else if (ci_equal(name, "Connection")) {
      ConnectionFlags flags = {scan->connection_close, scan->connection_keep_alive};
      (void)for_each_token(value, note_connection, &flags);
      scan->connection_close = flags.close;
      scan->connection_keep_alive = flags.keep_alive;
    }
  }
}

MsH1Scan ms_h1_scan(const MsHeaders *fields) {
  MsH1Scan scan = {.text = ms_headers_is_text(fields)};
  for (size_t g = 0; g < ms_headers_group_count(fields); g++) {
    scan_group(fields, g, &scan);
  }
  return scan;
}

bool ms_h1_scan_keep_alive(const MsH1Scan *scan, uint8_t minor) {
  return !scan->connection_close && (minor >= 1 || scan->connection_keep_alive);
}

typedef struct LengthState {
  bool found;
  uint64_t value;
  bool bad;
} LengthState;

static bool note_length(void *state, MsSpan part) {
  LengthState *length = state;
  uint64_t n = 0;
  if (part.len == 0) {
    length->bad = true;
    return false;
  }
  for (size_t i = 0; i < part.len; i++) {
    const uint8_t digit = (uint8_t)(part.ptr[i] - '0');
    if (digit > 9 || n > (UINT64_MAX - digit) / 10) {
      length->bad = true;
      return false;
    }
    n = n * 10 + digit;
  }
  if (length->found && length->value != n) {
    length->bad = true;
    return false;
  }
  length->found = true;
  length->value = n;
  return true;
}

/* The agreed Content-Length of the fields: false when a value is malformed or two disagree. */
static bool content_length(const MsHeaders *fields, bool *found, uint64_t *value) {
  LengthState length = {0};
  size_t group = 0;
  if (find_group(fields, "Content-Length", &group)) {
    for (size_t v = 0; v < ms_headers_group_size(fields, group) && !length.bad; v++) {
      (void)for_each_token(ms_headers_group_value(fields, group, v), note_length, &length);
    }
  }
  *found = length.found;
  *value = length.value;
  return !length.bad;
}

typedef struct EncodingList {
  size_t count;
  bool chunked_only;
} EncodingList;

static bool note_encoding(void *state, MsSpan token) {
  EncodingList *list = state;
  if (token.len > 0) {
    list->count++;
    list->chunked_only = list->count == 1 && ci_equal(token, "chunked");
  }
  return true;
}

bool ms_h1_request_framing(uint8_t minor, const MsHeaders *fields, const MsH1Scan *scan, MsH1Framing *out,
                           MsH1Bad *bad) {
  *out = (MsH1Framing){.kind = MS_H1_NO_BODY};
  if (!scan->transfer_encoding && !scan->content_length) {
    return true;
  }
  if (scan->transfer_encoding) {
    EncodingList list = {0};
    size_t group = 0;
    if (find_group(fields, "Transfer-Encoding", &group)) {
      for (size_t v = 0; v < ms_headers_group_size(fields, group); v++) {
        (void)for_each_token(ms_headers_group_value(fields, group, v), note_encoding, &list);
      }
    }
    /* Both framings make the request's end ambiguous between parsers: refuse it. */
    if (minor == 0 || scan->content_length) {
      *bad = (MsH1Bad){400, "Bad Request"};
      return false;
    }
    if (list.count == 1 && list.chunked_only) {
      out->kind = MS_H1_CHUNKED;
      return true;
    }
    *bad = (MsH1Bad){501, "Not Implemented"};
    return false;
  }
  bool found = false;
  uint64_t value = 0;
  if (!content_length(fields, &found, &value)) {
    *bad = (MsH1Bad){400, "Bad Request"};
    return false;
  }
  if (found && value > 0) {
    *out = (MsH1Framing){.kind = MS_H1_LENGTH, .length = value};
  }
  return true;
}
