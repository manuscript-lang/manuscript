/* Canonical text forms used to compare the C front end with the Rust one. */
#ifndef MS_DUMP_H
#define MS_DUMP_H

#include "ms/base.h"

/* Quotes `s` in the dump's string syntax: printable ASCII as is, other bytes as \xNN. */
void ms_dump_quote(MsBuf *out, const char *s, size_t n);
void ms_dump_pos(MsBuf *out, MsPos p);
/* "error line:col:off end=... fix=... opener=N "message"\n" */
void ms_dump_diag(MsBuf *out, const MsDiag *d);

#endif
