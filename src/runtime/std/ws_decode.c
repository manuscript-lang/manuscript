/* runtime/std/ws_decode.c: the resumable frame decoder: push bytes in, poll events out. Frames are checked
 * in RFC 6455 order and failures carry the texts the socket reports. */
#include "base/alloc.h"
#include "base/utf8.h"
#include "runtime/std/ws.h"

typedef enum Step { STEP_WAIT, STEP_AGAIN, STEP_EVENT, STEP_ERROR } Step;

MsWsDecoder ms_ws_decoder_new(bool server, bool deflate, uint64_t limit) {
  return (MsWsDecoder){.server = server, .deflate = deflate, .limit = limit, .kind = MS_WS_OP_BINARY};
}

void ms_ws_decoder_free(MsWsDecoder *decoder) {
  ms_bytes_free(&decoder->input);
  ms_bytes_free(&decoder->control);
  ms_bytes_free(&decoder->message);
}

void ms_ws_decoder_push(MsWsDecoder *decoder, MsSpan bytes) {
  if (decoder->start > 0 && decoder->start == decoder->input.len) {
    decoder->input.len = 0;
    decoder->start = 0;
  } else if (decoder->start > (size_t)1 << 16) {
    decoder->input.len -= decoder->start;
    __builtin_memmove(decoder->input.ptr, decoder->input.ptr + decoder->start, decoder->input.len);
    decoder->start = 0;
  }
  if (bytes.len > 0) {
    __builtin_memcpy(ms_list_extend(&decoder->input, 1, bytes.len), bytes.ptr, bytes.len);
  }
}

bool ms_ws_decoder_in_message(const MsWsDecoder *decoder) {
  return decoder->in_body;
}

void ms_ws_error_release(MsWsError *error) {
  ms_string_release(&error->text);
}

static Step fail_protocol(const MsWsDecoder *decoder, MsStrBuild *text, MsWsError *error) {
  *error =
      (MsWsError){.kind = MS_WS_ERR_PROTOCOL, .text = ms_strbuild_finish(text), .body = decoder->in_body};
  ms_strbuild_free(text);
  return STEP_ERROR;
}

static Step fail_text(const MsWsDecoder *decoder, const char *text, MsWsError *error) {
  MsStrBuild builder = ms_strbuild_new();
  ms_strbuild_append_text(&builder, text);
  return fail_protocol(decoder, &builder, error);
}

static Step fail_limit(const MsWsDecoder *decoder, MsWsError *error) {
  *error = (MsWsError){.kind = MS_WS_ERR_LIMIT, .reply_close = true, .body = decoder->in_body};
  return STEP_ERROR;
}

static void note_reason(MsStrBuild *reasons, const char *text) {
  if (ms_strbuild_length(reasons) > 0) {
    ms_strbuild_append_text(reasons, ", ");
  }
  ms_strbuild_append_text(reasons, text);
}

static bool is_control(uint8_t opcode) {
  return opcode == MS_WS_OP_CLOSE || opcode == MS_WS_OP_PING || opcode == MS_WS_OP_PONG;
}

/* The reasons the first two header bytes are wrong, collected into one comma-separated text. */
static void check_opcode(const MsWsDecoder *decoder, uint8_t b0, uint8_t b1, MsStrBuild *reasons) {
  const uint8_t opcode = b0 & 0x0f;
  if (is_control(opcode)) {
    if ((b1 & 0x7f) > MS_WS_MAX_CONTROL_PAYLOAD) {
      note_reason(reasons, "len > 125 for control");
    }
    if ((b0 & 0x80) == 0) {
      note_reason(reasons, "FIN not set on control");
    }
  } else if (opcode == MS_WS_OP_TEXT || opcode == MS_WS_OP_BINARY) {
    if (decoder->fragmenting) {
      note_reason(reasons, "data before FIN");
    }
  } else if (opcode == MS_WS_OP_CONTINUATION) {
    if (!decoder->fragmenting) {
      note_reason(reasons, "continuation after FIN");
    }
  } else {
    note_reason(reasons, "bad opcode ");
    ms_strbuild_append_u64(reasons, opcode);
  }
}

static Step check_first_two(const MsWsDecoder *decoder, uint8_t b0, uint8_t b1, MsWsError *error) {
  MsStrBuild reasons = ms_strbuild_new();
  const uint8_t opcode = b0 & 0x0f;
  if ((b0 & 0x40) != 0 && (!decoder->deflate || (opcode != MS_WS_OP_TEXT && opcode != MS_WS_OP_BINARY))) {
    note_reason(&reasons, "RSV1 set");
  }
  if ((b0 & 0x20) != 0) {
    note_reason(&reasons, "RSV2 set");
  }
  if ((b0 & 0x10) != 0) {
    note_reason(&reasons, "RSV3 set");
  }
  check_opcode(decoder, b0, b1, &reasons);
  if (((b1 & 0x80) != 0) != decoder->server) {
    note_reason(&reasons, "bad MASK");
  }
  if (ms_strbuild_length(&reasons) == 0) {
    ms_strbuild_free(&reasons);
    return STEP_AGAIN;
  }
  return fail_protocol(decoder, &reasons, error);
}

/* Message-size accounting of a data frame; a text or binary frame starts a new message. */
static Step accept_data_header(MsWsDecoder *decoder, uint8_t opcode, uint64_t length, bool compressed,
                               MsWsError *error) {
  const bool starts = opcode != MS_WS_OP_CONTINUATION;
  const uint64_t base = starts ? 0 : decoder->wire_len;
  if (length > (uint64_t)INT64_MAX || base > (uint64_t)INT64_MAX - length || base + length > decoder->limit) {
    return fail_limit(decoder, error);
  }
  decoder->wire_len = base + length;
  if (starts) {
    decoder->kind = opcode;
    decoder->compressed = compressed;
    decoder->message.len = 0;
    decoder->in_body = true;
  }
  return STEP_AGAIN;
}

static uint64_t read_length(MsSpan avail, uint8_t short_length) {
  uint64_t length = short_length;
  if (short_length == 126) {
    length = (uint64_t)avail.ptr[2] << 8 | avail.ptr[3];
  } else if (short_length == 127) {
    length = 0;
    for (size_t i = 0; i < 8; i++) {
      length = length << 8 | avail.ptr[2 + i];
    }
  }
  return length;
}

/* Parses one frame header if it is complete. */
static Step header(MsWsDecoder *decoder, MsWsError *error) {
  const MsSpan avail = ms_span_of(decoder->input.ptr + decoder->start, decoder->input.len - decoder->start);
  if (avail.len < 2) {
    return STEP_WAIT;
  }
  const uint8_t b0 = avail.ptr[0];
  const uint8_t b1 = avail.ptr[1];
  if (check_first_two(decoder, b0, b1, error) == STEP_ERROR) {
    return STEP_ERROR;
  }
  const uint8_t short_length = b1 & 0x7f;
  const bool masked = (b1 & 0x80) != 0;
  const size_t ext = short_length == 126 ? 2 : short_length == 127 ? 8 : 0;
  const size_t total = 2 + ext + (masked ? 4 : 0);
  if (avail.len < total) {
    return STEP_WAIT;
  }
  const uint64_t length = read_length(avail, short_length);
  /* RFC 6455 section 5.2 requires the shortest payload-length encoding. */
  if ((short_length == 126 && length < 126) || (short_length == 127 && length < 65536)) {
    return fail_text(decoder, "nonminimal payload length", error);
  }
  const uint8_t opcode = b0 & 0x0f;
  if (length > (uint64_t)INT64_MAX) {
    return fail_limit(decoder, error);
  }
  if (!is_control(opcode) && accept_data_header(decoder, opcode, length, (b0 & 0x40) != 0 && decoder->deflate,
                                                error) == STEP_ERROR) {
    return STEP_ERROR;
  }
  if (opcode == MS_WS_OP_TEXT || opcode == MS_WS_OP_BINARY || opcode == MS_WS_OP_CONTINUATION) {
    decoder->fragmenting = (b0 & 0x80) == 0;
  }
  decoder->opcode = opcode;
  decoder->fin = (b0 & 0x80) != 0;
  decoder->masked = masked;
  if (masked) {
    __builtin_memcpy(decoder->key, avail.ptr + 2 + ext, 4);
  }
  decoder->remaining = length;
  decoder->mask_pos = 0;
  decoder->control.len = 0;
  decoder->start += total;
  decoder->stage = MS_WS_STAGE_PAYLOAD;
  return STEP_AGAIN;
}

static Step close_event(const MsWsDecoder *decoder, MsSpan payload, MsWsEvent *event, MsWsError *error) {
  *event = (MsWsEvent){.kind = MS_WS_CLOSE, .code = MS_WS_CLOSE_NO_STATUS};
  if (payload.len == 0) {
    return STEP_EVENT;
  }
  if (payload.len == 1) {
    return fail_text(decoder, "close payload has one byte", error);
  }
  const uint16_t code = (uint16_t)(payload.ptr[0] << 8 | payload.ptr[1]);
  if (!ms_ws_valid_received_close_code(code)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "bad close code ");
    ms_strbuild_append_u64(&text, code);
    return fail_protocol(decoder, &text, error);
  }
  if (!ms_utf8_is_valid(payload.ptr + 2, payload.len - 2)) {
    *error = (MsWsError){.kind = MS_WS_ERR_INVALID_PAYLOAD};
    return STEP_ERROR;
  }
  event->code = code;
  event->data = ms_bytes_from_span(ms_span_of(payload.ptr + 2, payload.len - 2));
  return STEP_EVENT;
}

static Step control_event(MsWsDecoder *decoder, MsWsEvent *event, MsWsError *error) {
  const MsSpan payload = ms_bytes_span(&decoder->control);
  if (decoder->opcode == MS_WS_OP_CLOSE) {
    return close_event(decoder, payload, event, error);
  }
  *event = (MsWsEvent){.kind = decoder->opcode == MS_WS_OP_PING ? MS_WS_PING : MS_WS_PONG,
                       .data = ms_bytes_from_span(payload)};
  return STEP_EVENT;
}

static Step finish_message(MsWsDecoder *decoder, MsWsEvent *event, MsWsError *error) {
  decoder->in_body = false;
  MsBytes data = decoder->message;
  decoder->message = (MsBytes){0};
  if (decoder->compressed) {
    MsBytes inflated = {0};
    const MsWsInflate result = ms_ws_inflate_message(ms_bytes_span(&data), decoder->limit, &inflated);
    ms_bytes_free(&data);
    if (result != MS_WS_INFLATE_OK) {
      ms_bytes_free(&inflated);
      *error = (MsWsError){.kind = result == MS_WS_INFLATE_OVERFLOW ? MS_WS_ERR_OVERFLOW : MS_WS_ERR_CORRUPT};
      return STEP_ERROR;
    }
    data = inflated;
  }
  *event = (MsWsEvent){.kind = MS_WS_MESSAGE, .text = decoder->kind == MS_WS_OP_TEXT, .data = data};
  return STEP_EVENT;
}

static Step payload(MsWsDecoder *decoder, MsWsEvent *event, MsWsError *error) {
  const uint64_t avail = decoder->input.len - decoder->start;
  const size_t take = (size_t)(avail < decoder->remaining ? avail : decoder->remaining);
  if (take > 0) {
    MsBytes *sink = decoder->opcode >= MS_WS_OP_CLOSE ? &decoder->control : &decoder->message;
    uint8_t *to = ms_list_extend(sink, 1, take);
    __builtin_memcpy(to, decoder->input.ptr + decoder->start, take);
    if (decoder->masked) {
      decoder->mask_pos = ms_ws_mask_bytes(decoder->key, decoder->mask_pos, to, take);
    }
    decoder->remaining -= take;
    decoder->start += take;
  }
  if (decoder->remaining > 0) {
    return STEP_WAIT;
  }
  decoder->stage = MS_WS_STAGE_HEADER;
  if (decoder->opcode >= MS_WS_OP_CLOSE) {
    return control_event(decoder, event, error);
  }
  return decoder->fin ? finish_message(decoder, event, error) : STEP_AGAIN;
}

MsWsPoll ms_ws_decoder_poll(MsWsDecoder *decoder, MsWsEvent *event, MsWsError *error) {
  for (;;) {
    const Step step =
        decoder->stage == MS_WS_STAGE_HEADER ? header(decoder, error) : payload(decoder, event, error);
    if (step == STEP_WAIT) {
      return MS_WS_NEED_MORE;
    }
    if (step == STEP_EVENT) {
      return MS_WS_GOT_EVENT;
    }
    if (step == STEP_ERROR) {
      return MS_WS_GOT_ERROR;
    }
  }
}
