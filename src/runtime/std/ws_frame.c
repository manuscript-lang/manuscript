/* runtime/std/ws_frame.c: frame encoding, close payloads and the permessage-deflate transforms. */
#include <zlib.h>

#include "base/alloc.h"
#include "runtime/std/random.h"
#include "runtime/std/ws.h"

static bool is_close_code(uint16_t c) {
  switch (c) {
  case MS_WS_CLOSE_NORMAL:
  case MS_WS_CLOSE_GOING_AWAY:
  case MS_WS_CLOSE_PROTOCOL_ERROR:
  case MS_WS_CLOSE_UNSUPPORTED_DATA:
  case MS_WS_CLOSE_INVALID_PAYLOAD:
  case MS_WS_CLOSE_POLICY_VIOLATION:
  case MS_WS_CLOSE_MESSAGE_TOO_BIG:
  case MS_WS_CLOSE_MANDATORY_EXTENSION:
  case MS_WS_CLOSE_INTERNAL_ERROR:
  case MS_WS_CLOSE_SERVICE_RESTART:
  case MS_WS_CLOSE_TRY_AGAIN_LATER:
    return true;
  default:
    return false;
  }
}

bool ms_ws_valid_received_close_code(uint16_t code) {
  return is_close_code(code) || (code >= 3000 && code <= 4999);
}

static const char *close_name(uint16_t code) {
  switch (code) {
  case MS_WS_CLOSE_NORMAL:
    return " (normal)";
  case MS_WS_CLOSE_GOING_AWAY:
    return " (going away)";
  case MS_WS_CLOSE_PROTOCOL_ERROR:
    return " (protocol error)";
  case MS_WS_CLOSE_UNSUPPORTED_DATA:
    return " (unsupported data)";
  case MS_WS_CLOSE_NO_STATUS:
    return " (no status)";
  case MS_WS_CLOSE_ABNORMAL:
    return " (abnormal closure)";
  case MS_WS_CLOSE_INVALID_PAYLOAD:
    return " (invalid payload data)";
  case MS_WS_CLOSE_POLICY_VIOLATION:
    return " (policy violation)";
  case MS_WS_CLOSE_MESSAGE_TOO_BIG:
    return " (message too big)";
  case MS_WS_CLOSE_MANDATORY_EXTENSION:
    return " (mandatory extension missing)";
  case MS_WS_CLOSE_INTERNAL_ERROR:
    return " (internal server error)";
  case MS_WS_CLOSE_TLS_HANDSHAKE:
    return " (TLS handshake error)";
  default:
    return "";
  }
}

void ms_ws_close_error_text(uint16_t code, MsSpan reason, MsStrBuild *out) {
  ms_strbuild_append_text(out, "websocket: close ");
  ms_strbuild_append_u64(out, code);
  ms_strbuild_append_text(out, close_name(code));
  if (reason.len > 0) {
    ms_strbuild_append_text(out, ": ");
    ms_strbuild_append(out, reason);
  }
}

static void append_bytes(MsBytes *out, MsSpan data) {
  if (data.len > 0) {
    __builtin_memcpy(ms_list_extend(out, 1, data.len), data.ptr, data.len);
  }
}

void ms_ws_format_close(uint16_t code, MsSpan reason, MsBytes *out) {
  if (code == MS_WS_CLOSE_NO_STATUS) {
    return;
  }
  const uint8_t head[2] = {(uint8_t)(code >> 8), (uint8_t)code};
  append_bytes(out, ms_span_of(head, 2));
  append_bytes(out, reason);
}

void ms_ws_protocol_error_payload(MsSpan message, MsBytes *out) {
  ms_ws_format_close(MS_WS_CLOSE_PROTOCOL_ERROR, message, out);
  if (out->len > MS_WS_MAX_CONTROL_PAYLOAD) {
    out->len = MS_WS_MAX_CONTROL_PAYLOAD;
  }
}

size_t ms_ws_mask_bytes(const uint8_t key[4], size_t pos, uint8_t *data, size_t length) {
  for (size_t i = 0; i < length; i++) {
    data[i] ^= key[(pos + i) & 3];
  }
  return (pos + length) & 3;
}

bool ms_ws_new_mask_key(uint8_t key[4]) {
  MsBytes bytes = {0};
  MsString err = ms_string_empty();
  const bool ok = msstd_random_os_bytes(4, &bytes, &err) == MS_STATUS_OK && bytes.len == 4;
  if (ok) {
    __builtin_memcpy(key, bytes.ptr, 4);
  }
  ms_bytes_free(&bytes);
  ms_string_release(&err);
  return ok;
}

void ms_ws_encode_frame(MsBytes *out, uint8_t opcode, bool fin, bool rsv1, MsSpan payload,
                        const uint8_t *key) {
  const uint8_t b0 = (uint8_t)((opcode & 0x0f) | (fin ? 0x80 : 0) | (rsv1 ? 0x40 : 0));
  const uint8_t mask_bit = key != NULL ? 0x80 : 0;
  uint8_t head[14];
  size_t n = 0;
  head[n++] = b0;
  if (payload.len < 126) {
    head[n++] = (uint8_t)(mask_bit | payload.len);
  } else if (payload.len <= 0xffff) {
    head[n++] = (uint8_t)(mask_bit | 126);
    head[n++] = (uint8_t)(payload.len >> 8);
    head[n++] = (uint8_t)payload.len;
  } else {
    head[n++] = (uint8_t)(mask_bit | 127);
    for (int shift = 56; shift >= 0; shift -= 8) {
      head[n++] = (uint8_t)((uint64_t)payload.len >> shift);
    }
  }
  if (key != NULL) {
    __builtin_memcpy(head + n, key, 4);
    n += 4;
  }
  append_bytes(out, ms_span_of(head, n));
  const size_t start = out->len;
  append_bytes(out, payload);
  if (key != NULL) {
    (void)ms_ws_mask_bytes(key, 0, out->ptr + start, payload.len);
  }
}

bool ms_ws_encode_control(MsBytes *out, uint8_t opcode, MsSpan payload, bool masked) {
  uint8_t key[4];
  if (payload.len > MS_WS_MAX_CONTROL_PAYLOAD || (masked && !ms_ws_new_mask_key(key))) {
    return false;
  }
  ms_ws_encode_frame(out, opcode, true, false, payload, masked ? key : NULL);
  return true;
}

bool ms_ws_encode_message(MsBytes *out, uint8_t opcode, MsSpan payload, bool masked, bool compress,
                          size_t max_frame) {
  MsBytes deflated = {0};
  MsSpan body = payload;
  if (compress) {
    ms_ws_deflate_message(payload, &deflated);
    body = ms_bytes_span(&deflated);
  }
  const size_t size = max_frame == 0 ? (body.len > 0 ? body.len : 1) : max_frame;
  bool ok = true;
  size_t at = 0;
  bool first = true;
  do {
    const size_t take = body.len - at < size ? body.len - at : size;
    uint8_t key[4];
    if (masked && !ms_ws_new_mask_key(key)) {
      ok = false;
      break;
    }
    const bool last = at + take == body.len;
    ms_ws_encode_frame(out, first ? opcode : MS_WS_OP_CONTINUATION, last, first && compress,
                       ms_span_of(body.ptr + at, take), masked ? key : NULL);
    at += take;
    first = false;
  } while (at < body.len);
  ms_bytes_free(&deflated);
  return ok;
}

static const uint8_t SYNC_TAIL[4] = {0x00, 0x00, 0xff, 0xff};
/* What is appended before inflating: an empty stored block, then a final empty block. */
static const uint8_t INFLATE_TAIL[9] = {0x00, 0x00, 0xff, 0xff, 0x01, 0x00, 0x00, 0xff, 0xff};
enum { DEFLATE_LEVEL = 1, WINDOW_BITS = 15, CHUNK = 16384 };

void ms_ws_deflate_message(MsSpan data, MsBytes *out) {
  z_stream z = {0};
  if (deflateInit2(&z, DEFLATE_LEVEL, Z_DEFLATED, -WINDOW_BITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
    return;
  }
  z.next_in = (Bytef *)(uintptr_t)data.ptr;
  z.avail_in = (uInt)data.len;
  do {
    ms_list_reserve(out, 1, CHUNK);
    z.next_out = out->ptr + out->len;
    z.avail_out = CHUNK;
    if (deflate(&z, Z_SYNC_FLUSH) == Z_STREAM_ERROR) {
      break;
    }
    out->len += CHUNK - z.avail_out;
  } while (z.avail_out == 0);
  (void)deflateEnd(&z);
  if (out->len >= sizeof SYNC_TAIL &&
      ms_span_equal(ms_span_of(out->ptr + out->len - 4, 4), ms_span_of(SYNC_TAIL, 4))) {
    out->len -= sizeof SYNC_TAIL;
  }
}

/* Inflates input already holding the tail; stops with OVERFLOW once the output passes `max`. */
static MsWsInflate inflate_all(z_stream *z, uint64_t max, MsBytes *out) {
  for (;;) {
    ms_list_reserve(out, 1, CHUNK);
    z->next_out = out->ptr + out->len;
    z->avail_out = CHUNK;
    const uInt in_before = z->avail_in;
    const int status = inflate(z, Z_NO_FLUSH);
    const size_t produced = CHUNK - z->avail_out;
    out->len += produced;
    if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
      return MS_WS_INFLATE_CORRUPT;
    }
    if (out->len > max) {
      return MS_WS_INFLATE_OVERFLOW;
    }
    if (status == Z_STREAM_END) {
      return MS_WS_INFLATE_OK;
    }
    if (produced == 0 && z->avail_in == in_before) {
      return MS_WS_INFLATE_CORRUPT;
    }
  }
}

MsWsInflate ms_ws_inflate_message(MsSpan data, uint64_t max, MsBytes *out) {
  MsBytes input = {0};
  append_bytes(&input, data);
  append_bytes(&input, ms_span_of(INFLATE_TAIL, sizeof INFLATE_TAIL));
  z_stream z = {0};
  if (inflateInit2(&z, -WINDOW_BITS) != Z_OK) {
    ms_bytes_free(&input);
    return MS_WS_INFLATE_CORRUPT;
  }
  z.next_in = input.ptr;
  z.avail_in = (uInt)input.len;
  const MsWsInflate result = inflate_all(&z, max, out);
  (void)inflateEnd(&z);
  ms_bytes_free(&input);
  return result;
}
