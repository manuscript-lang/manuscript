/* What h2.c and h2_send.c share: the connection record and the per-stream send buffer. */
#ifndef MS_RUNTIME_STD_H2_INTERNAL_H
#define MS_RUNTIME_STD_H2_INTERNAL_H

#include <nghttp2/nghttp2.h>

#include "runtime/std/h2.h"

/* Body bytes accepted from the caller and not yet framed, with the end the caller asked for. */
typedef struct H2Out {
  int32_t id;
  MsBytes buffer;
  size_t position;
  bool eof;        /* every byte was accepted and the stream ends after them */
  bool deferred;   /* nghttp2 asked for data and there was none */
  MsList trailers; /* of MsH2Field, owned: sent instead of END_STREAM on the data */
  bool has_trailers;
} H2Out;

struct MsH2 {
  nghttp2_session *session;
  bool server;
  bool failed;
  MsList events; /* of MsH2Event; the first `head` were taken */
  size_t head;
  MsList block; /* of MsH2Field: the header block being received */
  size_t block_size;
  uint32_t max_header_list;
  MsList outs; /* of H2Out *: streams whose body this side is sending */
  size_t open;
};

/* h2.c */
MsH2Event *ms_h2_push_event(MsH2 *h2, MsH2EventKind kind, uint32_t id);
void ms_h2_fields_free(MsList *fields);

/* h2_send.c */
H2Out *ms_h2_out_find(const MsH2 *h2, int32_t id);
H2Out *ms_h2_out_new(MsH2 *h2, int32_t id);
void ms_h2_out_drop(MsH2 *h2, int32_t id);
void ms_h2_outs_free(MsH2 *h2);

#endif
