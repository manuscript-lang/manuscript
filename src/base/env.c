/* Owns reading the process environment (see env.h). */
#include "base/env.h"

#include <stdlib.h>

bool ms_env_get(const char *name, MsString *out) {
  // NOLINTNEXTLINE(concurrency-mt-unsafe): read before any thread starts.
  const char *value = getenv(name);
  if (value == NULL) {
    return false;
  }
  *out = ms_string_from_span(ms_span_of_text(value));
  return true;
}
