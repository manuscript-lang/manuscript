/* runtime/std/net_addr.c: host:port text shared by the network modules. */
#include "runtime/std/net_ip.h"

static bool has_byte(MsSpan text, uint8_t byte) {
  size_t at = 0;
  return ms_span_find(text, ms_span_of(&byte, 1), &at);
}

static bool has_bracket(MsSpan text) {
  return has_byte(text, '[') || has_byte(text, ']');
}

static bool split_bracketed(MsSpan rest, MsSpan *host, MsSpan *port) {
  size_t close = 0;
  const uint8_t bracket = ']';
  if (!ms_span_find(rest, ms_span_of(&bracket, 1), &close)) {
    return false;
  }
  MsSpan after = {0};
  if (!ms_span_slice(rest, 0, close, host) || !ms_span_slice(rest, close + 1, rest.len, &after) ||
      after.len == 0 || after.ptr[0] != ':' || !ms_span_slice(after, 1, after.len, port)) {
    return false;
  }
  return !has_byte(*port, ':') && !has_bracket(*port) && !has_byte(*host, '[');
}

bool ms_split_host_port(MsSpan text, MsSpan *host, MsSpan *port) {
  MsSpan rest = {0};
  if (text.len > 0 && text.ptr[0] == '[') {
    return ms_span_slice(text, 1, text.len, &rest) && split_bracketed(rest, host, port);
  }
  size_t colon = text.len;
  while (colon > 0 && text.ptr[colon - 1] != ':') {
    colon--;
  }
  if (colon == 0 || !ms_span_slice(text, 0, colon - 1, host) || !ms_span_slice(text, colon, text.len, port)) {
    return false;
  }
  return !has_byte(*host, ':') && !has_bracket(*host) && !has_bracket(*port);
}

bool ms_parse_port(MsSpan text, uint16_t *out) {
  uint32_t value = 0;
  if (text.len == 0 || text.len > 5) {
    return false;
  }
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] < '0' || text.ptr[i] > '9') {
      return false;
    }
    value = value * 10 + (uint32_t)(text.ptr[i] - '0');
  }
  if (value > 65535) {
    return false;
  }
  *out = (uint16_t)value;
  return true;
}

void ms_join_host_port(MsSpan host, uint16_t port, MsStrBuild *out) {
  const bool bracket = has_byte(host, ':');
  if (bracket) {
    ms_strbuild_append_byte(out, '[');
  }
  ms_strbuild_append(out, host);
  if (bracket) {
    ms_strbuild_append_byte(out, ']');
  }
  ms_strbuild_append_byte(out, ':');
  ms_strbuild_append_u64(out, port);
}
