/* base/float_parse.h: decimal text to a Float (float_parse.c). */
#ifndef MS_BASE_FLOAT_PARSE_H
#define MS_BASE_FLOAT_PARSE_H

#include "base/safe.h"

typedef enum MsParseFloat {
  MS_PARSE_FLOAT_OK,
  MS_PARSE_FLOAT_INVALID,     /* not a number */
  MS_PARSE_FLOAT_OUT_OF_RANGE /* a number too large for a Float */
} MsParseFloat;

/* Parses the whole text; `out` is written only on MS_PARSE_FLOAT_OK. */
MS_NODISCARD MsParseFloat ms_parse_float(MsSpan text, double *out);

#endif
