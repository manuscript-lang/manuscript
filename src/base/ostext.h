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
#ifdef _WIN32
/* UTF-16 text for the Windows API. Ownership: owned, freed with ms_os_wide_free. */
typedef struct MsOsWide {
  uint16_t *ptr; /* owned: UTF-16 units followed by a 0 unit; NULL when the span is not valid UTF-8 */
} MsOsWide;

/* `span` as UTF-16. With `as_path`, a drive or UNC path long enough to need it gets the extended-length
 * prefix and `\` separators. */
MsOsWide ms_os_wide_new(MsSpan span, bool as_path);
void ms_os_wide_free(MsOsWide *text);
#endif

#endif
