/* runtime/std/h2_send.c: what an HTTP/2 connection sends: heads, trailers, body bytes (buffered per stream
 * and framed as the peer's windows allow), resets, pings and GOAWAY. */
#include "base/alloc.h"
#include "runtime/std/h2_internal.h"

/* ---- per-stream body buffers ---- */

H2Out *ms_h2_out_find(const MsH2 *h2, int32_t id) {
  H2Out **items = (H2Out **)(void *)h2->outs.ptr;
  for (size_t i = 0; i < h2->outs.len; i++) {
    if (items[i]->id == id) {
      return items[i];
    }
  }
  return NULL;
}

H2Out *ms_h2_out_new(MsH2 *h2, int32_t id) {
  H2Out *out = ms_alloc_zeroed(sizeof *out);
  out->id = id;
  ms_list_push(&h2->outs, sizeof out, &out);
  return out;
}

static void out_free(H2Out *out) {
  ms_bytes_free(&out->buffer);
  ms_h2_fields_free(&out->trailers);
  ms_free(out);
}

void ms_h2_out_drop(MsH2 *h2, int32_t id) {
  H2Out **items = (H2Out **)(void *)h2->outs.ptr;
  for (size_t i = 0; i < h2->outs.len; i++) {
    if (items[i]->id == id) {
      out_free(items[i]);
      items[i] = items[--h2->outs.len];
      return;
    }
  }
}

void ms_h2_outs_free(MsH2 *h2) {
  H2Out **items = (H2Out **)(void *)h2->outs.ptr;
  for (size_t i = 0; i < h2->outs.len; i++) {
    out_free(items[i]);
  }
  ms_list_free(&h2->outs);
}

/* ---- header lists ---- */

static MsList make_nv(const MsH2Field *fields, size_t count) {
  MsList list = {0};
  for (size_t i = 0; i < count; i++) {
    const nghttp2_nv nv = {.name = fields[i].name.ptr,
                           .value = fields[i].value.ptr,
                           .namelen = fields[i].name.len,
                           .valuelen = fields[i].value.len,
                           .flags = NGHTTP2_NV_FLAG_NONE};
    ms_list_push(&list, sizeof nv, &nv);
  }
  return list;
}

/* ---- the body provider ---- */

static void send_trailers_now(MsH2 *h2, H2Out *out) {
  MsList nv = make_nv((const MsH2Field *)(const void *)out->trailers.ptr, out->trailers.len);
  (void)nghttp2_submit_trailer(h2->session, out->id, (const nghttp2_nv *)(void *)nv.ptr, nv.len);
  ms_list_free(&nv);
}

static nghttp2_ssize read_body(nghttp2_session *session, int32_t stream_id, uint8_t *buf, size_t length,
                               uint32_t *flags, nghttp2_data_source *source, void *user) {
  (void)session;
  (void)stream_id;
  MsH2 *h2 = user;
  H2Out *out = source->ptr;
  const size_t pending = out->buffer.len - out->position;
  const size_t n = pending < length ? pending : length;
  if (n > 0) {
    __builtin_memcpy(buf, out->buffer.ptr + out->position, n);
    out->position += n;
  }
  if (out->position == out->buffer.len) {
    out->buffer.len = 0;
    out->position = 0;
  }
  if (n == 0 && !out->eof) {
    out->deferred = true;
    return NGHTTP2_ERR_DEFERRED;
  }
  if (out->eof && out->buffer.len == 0) {
    *flags |= NGHTTP2_DATA_FLAG_EOF;
    if (out->has_trailers) {
      *flags |= NGHTTP2_DATA_FLAG_NO_END_STREAM;
      send_trailers_now(h2, out);
    }
  }
  return (nghttp2_ssize)n;
}

static nghttp2_data_provider2 provider_for(H2Out *out) {
  nghttp2_data_provider2 provider = {0};
  provider.source.ptr = out;
  provider.read_callback = read_body;
  return provider;
}

/* Wakes nghttp2 for a stream that had nothing to send. */
static void wake(MsH2 *h2, H2Out *out) {
  if (out->deferred) {
    out->deferred = false;
    (void)nghttp2_session_resume_data(h2->session, out->id);
  }
}

/* ---- heads ---- */

bool ms_h2_open_stream(MsH2 *h2, const MsH2Field *fields, size_t count, bool end_stream, uint32_t *id) {
  MsList nv = make_nv(fields, count);
  H2Out *out = end_stream ? NULL : ms_h2_out_new(h2, 0);
  const nghttp2_data_provider2 provider = out != NULL ? provider_for(out) : (nghttp2_data_provider2){0};
  const int32_t made = nghttp2_submit_request2(h2->session, NULL, (const nghttp2_nv *)(void *)nv.ptr, nv.len,
                                               out != NULL ? &provider : NULL, NULL);
  ms_list_free(&nv);
  if (made < 0) {
    if (out != NULL) {
      ms_h2_out_drop(h2, 0);
    }
    return false;
  }
  if (out != NULL) {
    out->id = made;
  }
  h2->open++;
  *id = (uint32_t)made;
  return true;
}

static bool is_interim(const MsH2Field *fields, size_t count) {
  for (size_t i = 0; i < count; i++) {
    const MsSpan name = ms_bytes_span(&fields[i].name);
    const MsSpan value = ms_bytes_span(&fields[i].value);
    if (ms_span_is_text(name, ":status")) {
      return value.len == 3 && value.ptr[0] == '1';
    }
  }
  return false;
}

bool ms_h2_send_response_headers(MsH2 *h2, uint32_t id, const MsH2Field *fields, size_t count,
                                 bool end_stream) {
  MsList nv = make_nv(fields, count);
  const nghttp2_nv *list = (const nghttp2_nv *)(void *)nv.ptr;
  int made;
  if (is_interim(fields, count)) {
    made = nghttp2_submit_headers(h2->session, NGHTTP2_FLAG_NONE, (int32_t)id, NULL, list, nv.len, NULL);
  } else {
    H2Out *out = end_stream ? NULL : ms_h2_out_new(h2, (int32_t)id);
    const nghttp2_data_provider2 provider = out != NULL ? provider_for(out) : (nghttp2_data_provider2){0};
    made = nghttp2_submit_response2(h2->session, (int32_t)id, list, nv.len, out != NULL ? &provider : NULL);
    if (made != 0 && out != NULL) {
      ms_h2_out_drop(h2, (int32_t)id);
    }
  }
  ms_list_free(&nv);
  return made == 0;
}

bool ms_h2_send_trailers(MsH2 *h2, uint32_t id, const MsH2Field *fields, size_t count) {
  H2Out *out = ms_h2_out_find(h2, (int32_t)id);
  if (out == NULL || out->eof) {
    return false;
  }
  for (size_t i = 0; i < count; i++) {
    const MsH2Field copy = {.name = ms_bytes_from_span(ms_bytes_span(&fields[i].name)),
                            .value = ms_bytes_from_span(ms_bytes_span(&fields[i].value))};
    ms_list_push(&out->trailers, sizeof copy, &copy);
  }
  out->has_trailers = true;
  out->eof = true;
  wake(h2, out);
  return true;
}

/* ---- body, windows, control frames ---- */

size_t ms_h2_window_available(const MsH2 *h2, uint32_t id) {
  const int32_t connection = nghttp2_session_get_remote_window_size(h2->session);
  const int32_t stream = nghttp2_session_get_stream_remote_window_size(h2->session, (int32_t)id);
  if (connection <= 0 || stream <= 0) {
    return 0;
  }
  size_t room = (size_t)(connection < stream ? connection : stream);
  const H2Out *out = ms_h2_out_find(h2, (int32_t)id);
  const size_t held = out != NULL ? out->buffer.len - out->position : 0;
  return room > held ? room - held : 0;
}

size_t ms_h2_send_data(MsH2 *h2, uint32_t id, MsSpan data, bool end_stream) {
  H2Out *out = ms_h2_out_find(h2, (int32_t)id);
  if (out == NULL || out->eof) {
    return 0;
  }
  const size_t room = ms_h2_window_available(h2, id);
  const size_t take = data.len < room ? data.len : room;
  if (take > 0) {
    __builtin_memcpy(ms_list_extend(&out->buffer, 1, take), data.ptr, take);
  }
  out->eof = end_stream && take == data.len;
  if (take > 0 || out->eof) {
    wake(h2, out);
  }
  return take;
}

void ms_h2_send_rst(MsH2 *h2, uint32_t id, uint32_t code) {
  (void)nghttp2_submit_rst_stream(h2->session, NGHTTP2_FLAG_NONE, (int32_t)id, code);
}

void ms_h2_release(MsH2 *h2, uint32_t id, size_t count) {
  if (count > 0) {
    (void)nghttp2_session_consume(h2->session, (int32_t)id, count);
  }
}

void ms_h2_send_ping(MsH2 *h2, const uint8_t data[8]) {
  (void)nghttp2_submit_ping(h2->session, NGHTTP2_FLAG_NONE, data);
}

void ms_h2_shutdown(MsH2 *h2, uint32_t code) {
  (void)nghttp2_submit_goaway(h2->session, NGHTTP2_FLAG_NONE,
                              nghttp2_session_get_last_proc_stream_id(h2->session), code, NULL, 0);
}
