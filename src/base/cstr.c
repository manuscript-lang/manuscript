/* Owns the libc string calls (see cstr.h). */
#include "base/cstr.h"

#include <string.h>

bool ms_cstr_equal(const char *left, const char *right) {
  return strcmp(left, right) == 0;
}
