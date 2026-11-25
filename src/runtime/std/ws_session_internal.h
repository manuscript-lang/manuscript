/* runtime/std/ws_session_internal.h: the session record shared by ws_session.c (writing, closing) and
 * ws_receive.c (reading). */
#ifndef MS_RUNTIME_STD_WS_SESSION_INTERNAL_H
#define MS_RUNTIME_STD_WS_SESSION_INTERNAL_H

#include <stdatomic.h>

#include "runtime/std/http_sync.h"
#include "runtime/std/ws_session.h"

/* A failure: a status and, for FAILED, its text. */
typedef struct MsWsFault {
  uint8_t status;
  MsString text;
} MsWsFault;

struct MsWsSession {
  atomic_uint handles;
  MsWsTransport io;
  MsWsConfig config;
  MsWsDecoder decoder;
  MsHttpMutex *lock; /* guards queue, flushing and the sticky write failure */
  MsList queue;      /* MsBytes of frames waiting behind a write in progress */
  bool flushing;
  MsWsFault write_fault; /* a failed write or a sent close frame: sticky */
  atomic_bool reading;
  atomic_bool closed; /* close() ran */
  atomic_bool failed; /* an earlier read failure ended the session */
};

#define MS_WS_CONTROL_WRITE_NS ((int64_t)1000000000)
#define MS_WS_CLOSE_WRITE_NS ((int64_t)100000000)
#define MS_WS_MAX_CLOSE_REASON ((size_t)123)

/* Wording of a failure inside a message body. */
extern const char ms_ws_truncated_text[];

MsWsFault ms_ws_fault(uint8_t status);
MsWsFault ms_ws_fault_text(const char *text);
MsWsFault ms_ws_fault_string(MsStrBuild *text);
void ms_ws_fault_release(MsWsFault *fault);
/* Moves the fault into `err` and returns its status. */
uint8_t ms_ws_fault_take(MsWsFault *fault, MsString *err);

bool ms_ws_session_ended(MsWsSession *session);
/* Ends the session after a read failure. */
void ms_ws_session_fail(MsWsSession *session);
/* A control frame; a sent close frame makes later writes fail. */
MsWsFault ms_ws_session_control(MsWsSession *session, uint8_t opcode, MsSpan payload, int64_t timeout_ns,
                                const char *on_timeout);
/* A close frame, best effort. */
void ms_ws_session_send_close(MsWsSession *session, uint16_t code, MsSpan reason, int64_t timeout_ns);

#endif
