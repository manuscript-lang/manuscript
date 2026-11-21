/* base/float_table.h: the table behind the shortest-float digits (float_table.c). */
#ifndef MS_BASE_FLOAT_TABLE_H
#define MS_BASE_FLOAT_TABLE_H

#include "base/safe.h"

#define MS_FLOAT_K_MIN (-324)

extern const uint64_t ms_float_g[617][2];

#endif
