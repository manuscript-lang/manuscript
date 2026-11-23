/* runtime/std/h2.c: the HTTP/2 connection on nghttp2: session setup, the callbacks that turn frames into
 * events, and feeding and draining bytes. Sending is in h2_send.c. */
#include "base/alloc.h"
#include "runtime/std/h2_internal.h"

enum { DEFAULT_WINDOW = 65535, HEADER_ENTRY_OVERHEAD = 32 };

void ms_h2_fields_free(MsList *fields) {
  MsH2Field *items = (MsH2Field *)(void *)fields->ptr;
  for (size_t i = 0; i < fields->len; i++) {
    ms_bytes_free(&items[i].name);
    ms_bytes_free(&items[i].value);
  }
  ms_list_free(fields);
}

MsH2Event *ms_h2_push_event(MsH2 *h2, MsH2EventKind kind, uint32_t id) {
  const MsH2Event event = {.kind = kind, .id = id};
  ms_list_push(&h2->events, sizeof event, &event);
  return (MsH2Event *)(void *)h2->events.ptr + (h2->events.len - 1);
}

void ms_h2_event_release(MsH2Event *event) {
  ms_h2_fields_free(&event->fields);
  ms_bytes_free(&event->data);
}

bool ms_h2_poll(MsH2 *h2, MsH2Event *out) {
  if (h2->head >= h2->events.len) {
    h2->head = 0;
    h2->events.len = 0;
    return false;
  }
  *out = ((MsH2Event *)(void *)h2->events.ptr)[h2->head++];
  return true;
}

/* ---- nghttp2 callbacks ---- */

static int on_begin_headers(nghttp2_session *session, const nghttp2_frame *frame, void *user) {
  (void)session;
  MsH2 *h2 = user;
  if (frame->hd.type != NGHTTP2_HEADERS) {
    return 0;
  }
  ms_h2_fields_free(&h2->block);
  h2->block_size = 0;
  if (h2->server && frame->headers.cat == NGHTTP2_HCAT_REQUEST) {
    h2->open++;
  }
  return 0;
}

static int on_header(nghttp2_session *session, const nghttp2_frame *frame, const uint8_t *name,
                     size_t name_len, const uint8_t *value, size_t value_len, uint8_t flags, void *user) {
  (void)session;
  (void)frame;
  (void)flags;
  MsH2 *h2 = user;
  h2->block_size += name_len + value_len + HEADER_ENTRY_OVERHEAD;
  if (h2->max_header_list != 0 && h2->block_size > h2->max_header_list) {
    return NGHTTP2_ERR_TEMPORAL_CALLBACK_FAILURE;
  }
  const MsH2Field field = {.name = ms_bytes_from_span(ms_span_of(name, name_len)),
                           .value = ms_bytes_from_span(ms_span_of(value, value_len))};
  ms_list_push(&h2->block, sizeof field, &field);
  return 0;
}

static int on_data_chunk(nghttp2_session *session, uint8_t flags, int32_t stream_id, const uint8_t *data,
                         size_t len, void *user) {
  (void)session;
  (void)flags;
  MsH2Event *event = ms_h2_push_event(user, MS_H2_DATA, (uint32_t)stream_id);
  event->data = ms_bytes_from_span(ms_span_of(data, len));
  return 0;
}

/* The end of a DATA frame: marks the stream's last chunk, or adds an empty one (nghttp2 returns the padding).
 */
static void data_frame_done(MsH2 *h2, const nghttp2_frame *frame) {
  const uint32_t id = (uint32_t)frame->hd.stream_id;
  if ((frame->hd.flags & NGHTTP2_FLAG_END_STREAM) == 0) {
    return;
  }
  MsH2Event *last =
      h2->events.len > h2->head ? (MsH2Event *)(void *)h2->events.ptr + (h2->events.len - 1) : NULL;
  if (last == NULL || last->kind != MS_H2_DATA || last->id != id || last->end_stream) {
    last = ms_h2_push_event(h2, MS_H2_DATA, id);
  }
  last->end_stream = true;
}

static void settings_frame_done(MsH2 *h2, const nghttp2_frame *frame) {
  if ((frame->hd.flags & NGHTTP2_FLAG_ACK) != 0) {
    (void)ms_h2_push_event(h2, MS_H2_SETTINGS_ACKED, 0);
  } else {
    /* A larger initial window opens every stream's send window. */
    (void)ms_h2_push_event(h2, MS_H2_WINDOW_OPENED, 0);
  }
}

static void goaway_frame_done(MsH2 *h2, const nghttp2_frame *frame) {
  MsH2Event *event = ms_h2_push_event(h2, MS_H2_GOAWAY, 0);
  event->last_stream_id = (uint32_t)frame->goaway.last_stream_id;
  event->code = frame->goaway.error_code;
  event->data = ms_bytes_from_span(ms_span_of(frame->goaway.opaque_data, frame->goaway.opaque_data_len));
}

static int on_frame_recv(nghttp2_session *session, const nghttp2_frame *frame, void *user) {
  (void)session;
  MsH2 *h2 = user;
  const uint32_t id = (uint32_t)frame->hd.stream_id;
  switch (frame->hd.type) {
  case NGHTTP2_HEADERS: {
    MsH2Event *event = ms_h2_push_event(h2, MS_H2_HEADERS, id);
    event->fields = h2->block;
    event->end_stream = (frame->hd.flags & NGHTTP2_FLAG_END_STREAM) != 0;
    h2->block = (MsList){0};
    break;
  }
  case NGHTTP2_DATA:
    data_frame_done(h2, frame);
    break;
  case NGHTTP2_RST_STREAM:
    /* A nonzero code is reported when the stream closes. */
    if (frame->rst_stream.error_code == NGHTTP2_NO_ERROR) {
      (void)ms_h2_push_event(h2, MS_H2_RESET, id);
    }
    break;
  case NGHTTP2_GOAWAY:
    goaway_frame_done(h2, frame);
    break;
  case NGHTTP2_WINDOW_UPDATE:
    (void)ms_h2_push_event(h2, MS_H2_WINDOW_OPENED, id);
    break;
  case NGHTTP2_SETTINGS:
    settings_frame_done(h2, frame);
    break;
  case NGHTTP2_PING:
    if ((frame->hd.flags & NGHTTP2_FLAG_ACK) != 0) {
      MsH2Event *event = ms_h2_push_event(h2, MS_H2_PING_ACK, 0);
      __builtin_memcpy(event->ping, frame->ping.opaque_data, sizeof event->ping);
    }
    break;
  default:
    break;
  }
  return 0;
}

static int on_stream_close(nghttp2_session *session, int32_t stream_id, uint32_t error_code, void *user) {
  (void)session;
  MsH2 *h2 = user;
  if (h2->open > 0) {
    h2->open--;
  }
  ms_h2_out_drop(h2, stream_id);
  if (error_code != NGHTTP2_NO_ERROR) {
    ms_h2_push_event(h2, MS_H2_RESET, (uint32_t)stream_id)->code = error_code;
  }
  return 0;
}

/* ---- the connection ---- */

static nghttp2_session_callbacks *make_callbacks(void) {
  nghttp2_session_callbacks *callbacks = NULL;
  (void)nghttp2_session_callbacks_new(&callbacks);
  nghttp2_session_callbacks_set_on_begin_headers_callback(callbacks, on_begin_headers);
  nghttp2_session_callbacks_set_on_header_callback(callbacks, on_header);
  nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, on_data_chunk);
  nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, on_frame_recv);
  nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, on_stream_close);
  return callbacks;
}

static size_t settings_entries(bool server, const MsH2Settings *s, nghttp2_settings_entry entries[6]) {
  size_t count = 0;
  if (s->max_concurrent != 0) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, s->max_concurrent};
  }
  if (s->initial_window != 0) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE, s->initial_window};
  }
  if (s->max_frame_size != 0) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_FRAME_SIZE, s->max_frame_size};
  }
  if (s->max_header_list != 0) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_HEADER_LIST_SIZE, s->max_header_list};
  }
  if (s->header_table_size != 0) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_HEADER_TABLE_SIZE, s->header_table_size};
  }
  if (!server) {
    entries[count++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_ENABLE_PUSH, 0};
  }
  return count;
}

MsH2 *ms_h2_new(bool server, const MsH2Settings *settings) {
  MsH2 *h2 = ms_alloc_zeroed(sizeof *h2);
  h2->server = server;
  h2->max_header_list = settings->max_header_list;
  nghttp2_session_callbacks *callbacks = make_callbacks();
  nghttp2_option *option = NULL;
  (void)nghttp2_option_new(&option);
  nghttp2_option_set_no_auto_window_update(option, 1);
  const int made = server ? nghttp2_session_server_new3(&h2->session, callbacks, h2, option, NULL)
                          : nghttp2_session_client_new3(&h2->session, callbacks, h2, option, NULL);
  nghttp2_option_del(option);
  nghttp2_session_callbacks_del(callbacks);
  if (made != 0) {
    ms_free(h2);
    return NULL;
  }
  nghttp2_settings_entry entries[6];
  const size_t count = settings_entries(server, settings, entries);
  (void)nghttp2_submit_settings(h2->session, NGHTTP2_FLAG_NONE, entries, count);
  if (settings->connection_window > DEFAULT_WINDOW) {
    (void)nghttp2_session_set_local_window_size(h2->session, NGHTTP2_FLAG_NONE, 0,
                                                (int32_t)settings->connection_window);
  }
  return h2;
}

void ms_h2_free(MsH2 *h2) {
  if (h2 == NULL) {
    return;
  }
  for (size_t i = h2->head; i < h2->events.len; i++) {
    ms_h2_event_release((MsH2Event *)(void *)h2->events.ptr + i);
  }
  ms_list_free(&h2->events);
  ms_h2_fields_free(&h2->block);
  ms_h2_outs_free(h2);
  nghttp2_session_del(h2->session);
  ms_free(h2);
}

bool ms_h2_feed(MsH2 *h2, MsSpan input) {
  if (h2->failed) {
    return false;
  }
  const nghttp2_ssize used = nghttp2_session_mem_recv2(h2->session, input.ptr, input.len);
  if (used < 0) {
    h2->failed = true;
    h2->error = nghttp2_strerror((int)used);
    return false;
  }
  return true;
}

void ms_h2_take_output(MsH2 *h2, MsBytes *out) {
  for (;;) {
    const uint8_t *chunk = NULL;
    const nghttp2_ssize n = nghttp2_session_mem_send2(h2->session, &chunk);
    if (n <= 0) {
      return;
    }
    __builtin_memcpy(ms_list_extend(out, 1, (size_t)n), chunk, (size_t)n);
  }
}

bool ms_h2_wants_write(const MsH2 *h2) {
  return nghttp2_session_want_write(h2->session) != 0;
}

bool ms_h2_failed(const MsH2 *h2) {
  return h2->failed;
}

const char *ms_h2_error_text(const MsH2 *h2) {
  return h2->error != NULL ? h2->error : "";
}

size_t ms_h2_open_streams(const MsH2 *h2) {
  return h2->open;
}
