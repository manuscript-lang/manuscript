/* The source formatter. */
#ifndef MS_FORMAT_H
#define MS_FORMAT_H

#include "ms/base.h"

/* Formats `src` (UTF-8, any line ends). On success appends the formatted text to `out` and returns
 * true. Invalid syntax never produces output: the first syntax error fills *diag, with its message
 * allocated in `arena`, and the function returns false. */
bool ms_format(MsArena *arena, const char *src, size_t len, MsBuf *out, MsDiag *diag);

#endif
