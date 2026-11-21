/* runtime/std/http_target.c: request targets: percent-decoding and the path normalization of the server. */
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/std/http_wire.h"

static bool is_authority_byte(uint8_t b) {
  if ((b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')) {
    return true;
  }
  size_t at = 0;
  return b != 0 && ms_span_find(ms_span_of_text("-._~%!$&'()*+,;=:[]"), ms_span_of(&b, 1), &at);
}

bool ms_http_valid_authority(MsSpan value) {
  for (size_t i = 0; i < value.len; i++) {
    if (!is_authority_byte(value.ptr[i])) {
      return false;
    }
  }
  return true;
}

static int hex_value(uint8_t b) {
  if (b >= '0' && b <= '9') {
    return b - '0';
  }
  if (b >= 'a' && b <= 'f') {
    return b - 'a' + 10;
  }
  return b >= 'A' && b <= 'F' ? b - 'A' + 10 : -1;
}

bool ms_http_unescape(MsSpan raw, MsString *out) {
  MsStrBuild text = ms_strbuild_new();
  for (size_t i = 0; i < raw.len;) {
    if (raw.ptr[i] != '%') {
      ms_strbuild_append_byte(&text, raw.ptr[i++]);
      continue;
    }
    const int hi = i + 1 < raw.len ? hex_value(raw.ptr[i + 1]) : -1;
    const int lo = i + 2 < raw.len ? hex_value(raw.ptr[i + 2]) : -1;
    if (hi < 0 || lo < 0) {
      ms_strbuild_free(&text);
      return false;
    }
    ms_strbuild_append_byte(&text, (uint8_t)(hi << 4 | lo));
    i += 3;
  }
  *out = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
  return true;
}

typedef struct SpanList {
  MsSpan *ptr;
  size_t len;
  size_t cap;
} SpanList;

static bool is_dotdot(MsSpan s) {
  return ms_span_is_text(s, "..");
}

/* One segment of the path: drops "" and ".", and lets ".." pop (or stay when the path is relative). */
static void clean_segment(SpanList *stack, MsSpan seg, bool rooted) {
  if (seg.len == 0 || ms_span_is_text(seg, ".")) {
    return;
  }
  if (!is_dotdot(seg)) {
    ms_list_push((MsList *)(void *)stack, sizeof seg, &seg);
    return;
  }
  if (stack->len > 0 && !is_dotdot(stack->ptr[stack->len - 1])) {
    stack->len--;
  } else if (!rooted) {
    ms_list_push((MsList *)(void *)stack, sizeof seg, &seg);
  }
}

MsString ms_http_clean_path(MsSpan path) {
  const bool rooted = path.len > 0 && path.ptr[0] == '/';
  SpanList stack = {0};
  size_t start = 0;
  for (size_t i = 0; i <= path.len; i++) {
    if (i == path.len || path.ptr[i] == '/') {
      clean_segment(&stack, ms_span_of(path.ptr + start, i - start), rooted);
      start = i + 1;
    }
  }
  MsStrBuild out = ms_strbuild_new();
  if (rooted) {
    ms_strbuild_append_byte(&out, '/');
  }
  for (size_t i = 0; i < stack.len; i++) {
    if (i > 0) {
      ms_strbuild_append_byte(&out, '/');
    }
    ms_strbuild_append(&out, stack.ptr[i]);
  }
  const bool empty = stack.len == 0;
  ms_list_free((MsList *)(void *)&stack);
  if (!rooted && empty) {
    ms_strbuild_append_byte(&out, '.');
  }
  const bool dir = path.len > 0 && path.ptr[path.len - 1] == '/';
  if (dir && !(out.bytes.len == 1 && out.bytes.ptr[0] == '/')) {
    ms_strbuild_append_byte(&out, '/');
  }
  MsString result = ms_strbuild_finish(&out);
  ms_strbuild_free(&out);
  return result;
}

static bool find_byte(MsSpan s, uint8_t b, size_t *at) {
  return ms_span_find(s, ms_span_of(&b, 1), at);
}

/* `rest` without a fragment, split at the first `?`. */
static void split_query(MsSpan rest, MsSpan *path, MsSpan *query) {
  size_t at = 0;
  if (find_byte(rest, '#', &at)) {
    rest.len = at;
  }
  if (find_byte(rest, '?', &at)) {
    *path = ms_span_of(rest.ptr, at);
    *query = ms_span_of(rest.ptr + at + 1, rest.len - at - 1);
    return;
  }
  *path = rest;
  *query = ms_span_of(NULL, 0);
}

static bool has_text_ci(MsSpan s, const char *needle_lower) {
  const MsSpan needle = ms_span_of_text(needle_lower);
  for (size_t i = 0; i + needle.len <= s.len; i++) {
    bool same = true;
    for (size_t j = 0; j < needle.len && same; j++) {
      const uint8_t c = s.ptr[i + j];
      same = (uint8_t)(c >= 'A' && c <= 'Z' ? c + 32 : c) == needle.ptr[j];
    }
    if (same) {
      return true;
    }
  }
  return false;
}

static bool has_nul(MsSpan s) {
  size_t at = 0;
  return find_byte(s, 0, &at);
}

/* Strips an http:// or https:// prefix, recording the authority up to the first / or ?. */
static bool take_authority(MsSpan *rest, MsSpan *host, bool *has_host, const char **reason) {
  MsSpan after = {0};
  if (ms_span_starts_with(*rest, ms_span_of_text("http://"))) {
    after = ms_span_of(rest->ptr + 7, rest->len - 7);
  } else if (ms_span_starts_with(*rest, ms_span_of_text("https://"))) {
    after = ms_span_of(rest->ptr + 8, rest->len - 8);
  } else {
    return true;
  }
  size_t end = 0;
  while (end < after.len && after.ptr[end] != '/' && after.ptr[end] != '?') {
    end++;
  }
  *host = ms_span_of(after.ptr, end);
  if (!ms_http_valid_authority(*host)) {
    *reason = "invalid Host";
    return false;
  }
  *has_host = true;
  *rest = ms_span_of(after.ptr + end, after.len - end);
  return true;
}

static bool finish_path(MsSpan raw_path, MsString *path, const char **reason) {
  MsString decoded = ms_string_empty();
  if (!ms_http_unescape(raw_path, &decoded)) {
    *reason = "Bad Request";
    return false;
  }
  const MsSpan bytes = ms_string_span(&decoded);
  if (!ms_utf8_is_valid(bytes.ptr, bytes.len)) {
    *reason = "invalid UTF-8 URL";
  } else if (has_text_ci(raw_path, "%00") || has_text_ci(raw_path, "%2f") || has_nul(bytes)) {
    *reason = "invalid request path";
  }
  if (*reason != NULL) {
    ms_string_release(&decoded);
    return false;
  }
  if (bytes.len > 0 && bytes.ptr[0] == '/') {
    *path = ms_http_clean_path(bytes);
    ms_string_release(&decoded);
  } else {
    *path = decoded;
  }
  return true;
}

bool ms_http_target_parse(MsSpan target, MsHttpTarget *out, const char **reason) {
  *reason = NULL;
  for (size_t i = 0; i < target.len; i++) {
    if (target.ptr[i] < 0x20 || target.ptr[i] == 0x7f || target.ptr[i] == ' ') {
      *reason = "Bad Request";
      return false;
    }
  }
  MsSpan host = {0};
  bool has_host = false;
  MsSpan rest = target;
  if (!take_authority(&rest, &host, &has_host, reason)) {
    return false;
  }
  MsSpan raw_path = {0};
  MsSpan query = {0};
  split_query(rest, &raw_path, &query);
  if (raw_path.len == 0 && has_host) {
    raw_path = ms_span_of_text("/");
  }
  MsString path = ms_string_empty();
  if (ms_span_is_text(raw_path, "*")) {
    path = ms_string_from_span(raw_path);
  } else if (!ms_utf8_is_valid(query.ptr, query.len)) {
    *reason = "invalid UTF-8 URL";
    return false;
  } else if (!finish_path(raw_path, &path, reason)) {
    return false;
  }
  *out = (MsHttpTarget){.path = path,
                        .query = ms_string_from_span(query),
                        .has_host = has_host,
                        .host = has_host ? ms_string_from_span(host) : ms_string_empty()};
  return true;
}

void ms_http_target_release(MsHttpTarget *target) {
  ms_string_release(&target->path);
  ms_string_release(&target->query);
  ms_string_release(&target->host);
}
