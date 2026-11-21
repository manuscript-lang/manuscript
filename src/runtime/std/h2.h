/* runtime/std/h2.h: a sans-io HTTP/2 connection on nghttp2, for client and server (h2.c: session, events;
 * h2_send.c: what a caller sends). It owns no socket, thread or clock: the caller feeds received bytes with
 * ms_h2_feed, writes what ms_h2_take_output returns, and reads what happened with ms_h2_poll.
 *
 * Receive flow control is explicit: every DATA byte handed out in an event stays charged against the peer's
 * windows until the caller returns it with ms_h2_release; padding is returned for it. Sending honors the
 * peer's windows: ms_h2_send_data returns how many bytes it took and the caller retries the rest after a
 * MS_H2_WINDOW_OPENED event. A connection error makes ms_h2_feed return false; the GOAWAY is queued in the
 * output (drain it before closing) and every later feed fails again. Header names go out as given, so callers
 * lower-case them. */
#ifndef MS_RUNTIME_STD_H2_H
#define MS_RUNTIME_STD_H2_H

#include "base/bytes.h"

/* RFC 9113 section 7 error codes. */
enum {
  MS_H2_NO_ERROR = 0x0,
  MS_H2_PROTOCOL_ERROR = 0x1,
  MS_H2_INTERNAL_ERROR = 0x2,
  MS_H2_FLOW_CONTROL_ERROR = 0x3,
  MS_H2_STREAM_CLOSED = 0x5,
  MS_H2_FRAME_SIZE_ERROR = 0x6,
  MS_H2_REFUSED_STREAM = 0x7,
  MS_H2_CANCEL = 0x8,
  MS_H2_COMPRESSION_ERROR = 0x9,
  MS_H2_ENHANCE_YOUR_CALM = 0xb
};

typedef struct MsH2 MsH2;

/* One header field. In events both are owned; a caller sending may pass views (ms_bytes_view). */
typedef struct MsH2Field {
  MsBytes name;
  MsBytes value;
} MsH2Field;

/* Zero means the protocol default (or, for max_concurrent and max_header_list, unlimited and unadvertised).
 */
typedef struct MsH2Settings {
  uint32_t header_table_size;
  uint32_t max_concurrent; /* streams the peer may open */
  uint32_t initial_window; /* per stream we receive on */
  uint32_t max_frame_size;
  uint32_t max_header_list;
  uint32_t connection_window; /* target connection receive window; more than 65535 is granted at startup */
} MsH2Settings;

typedef enum MsH2EventKind {
  MS_H2_HEADERS,        /* a complete block: request, response (also 1xx) or trailers; `fields` */
  MS_H2_DATA,           /* body bytes in `data`; return them with ms_h2_release */
  MS_H2_RESET,          /* the stream ended with `code` (also a stream error raised here) */
  MS_H2_GOAWAY,         /* the peer is shutting down: `last_stream_id`, `code`, debug text in `data` */
  MS_H2_WINDOW_OPENED,  /* the send window of `id` grew (0: the connection's, or a setting changed) */
  MS_H2_SETTINGS_ACKED, /* the peer acknowledged our SETTINGS */
  MS_H2_PING_ACK        /* a PING we sent was answered: `ping` */
} MsH2EventKind;

typedef struct MsH2Event {
  MsH2EventKind kind;
  uint32_t id;
  bool end_stream; /* HEADERS and DATA: the peer's side of the stream ends here */
  uint32_t code;
  uint32_t last_stream_id;
  MsList fields; /* of MsH2Field */
  MsBytes data;
  uint8_t ping[8];
} MsH2Event;

MsH2 *ms_h2_new(bool server, const MsH2Settings *settings);
void ms_h2_free(MsH2 *h2);

/* Processes received bytes; false on a connection error (ms_h2_error_text says which). */
MS_NODISCARD bool ms_h2_feed(MsH2 *h2, MsSpan input);
/* Takes the next event into `out` (release it with ms_h2_event_release); false when none is pending. */
MS_NODISCARD bool ms_h2_poll(MsH2 *h2, MsH2Event *out);
void ms_h2_event_release(MsH2Event *event);
/* Appends the bytes to write to `out`. */
void ms_h2_take_output(MsH2 *h2, MsBytes *out);
bool ms_h2_failed(const MsH2 *h2);
const char *ms_h2_error_text(const MsH2 *h2);
/* Streams in flight (opened and not yet closed). */
size_t ms_h2_open_streams(const MsH2 *h2);
/* Bytes ms_h2_send_data would take now on stream `id`. */
size_t ms_h2_window_available(const MsH2 *h2, uint32_t id);

/* Client: opens a stream with a request head; `*id` is the new stream. False when refused locally. */
MS_NODISCARD bool ms_h2_open_stream(MsH2 *h2, const MsH2Field *fields, size_t count, bool end_stream,
                                    uint32_t *id);
/* Server: the response head (a 1xx status is an interim response and leaves the stream open). */
MS_NODISCARD bool ms_h2_send_response_headers(MsH2 *h2, uint32_t id, const MsH2Field *fields, size_t count,
                                              bool end_stream);
/* Ends a stream that is sending a body with trailers (instead of end_stream on the last data). */
MS_NODISCARD bool ms_h2_send_trailers(MsH2 *h2, uint32_t id, const MsH2Field *fields, size_t count);
/* Takes up to the open send window of `data`; the return value is how many bytes were taken. `end_stream`
 * only takes effect once every byte was taken. */
size_t ms_h2_send_data(MsH2 *h2, uint32_t id, MsSpan data, bool end_stream);
void ms_h2_send_rst(MsH2 *h2, uint32_t id, uint32_t code);
/* Returns `count` received DATA bytes of stream `id` to the peer's window. */
void ms_h2_release(MsH2 *h2, uint32_t id, size_t count);
void ms_h2_send_ping(MsH2 *h2, const uint8_t data[8]);
/* GOAWAY with `code`; in-flight streams may finish. */
void ms_h2_shutdown(MsH2 *h2, uint32_t code);

#endif
