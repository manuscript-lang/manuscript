/* base/env.h: process environment variables. */
#ifndef MS_BASE_ENV_H
#define MS_BASE_ENV_H

#include "base/string.h"

/* Copies the value of the variable `name` (a string literal) into `*out`; false when it is unset. */
MS_NODISCARD MS_NONNULL bool ms_env_get(const char *name, MsString *out);

#endif
