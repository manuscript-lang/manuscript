/* base/ostext.h: the NUL-terminated copy of a span that an OS call needs, and the OS error text.
 *
 * Ownership: an MsOsText owns its bytes and ends with ms_os_text_free. */
#ifndef MS_BASE_OSTEXT_H
#define MS_BASE_OSTEXT_H

#include "base/strbuild.h"

typedef struct MsOsText {
  char *ptr; /* owned: the bytes of the span followed by a NUL */
} MsOsText;

/* A NUL-terminated copy of `span`. */
MsOsText ms_os_text_new(MsSpan span);
void ms_os_text_free(MsOsText *text);

/* Appends the system message of the C error number `error_number`. */
void ms_os_error_text(int error_number, MsStrBuild *out);

#endif
