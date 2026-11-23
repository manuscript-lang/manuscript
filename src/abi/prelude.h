/* abi/prelude.h: the type names every module sees without importing them: the primitives, and the interfaces and
 * collections the prelude declares (stdlib/core). The checker, the tooling and the editor all read these lists. */
#ifndef MS_ABI_PRELUDE_H
#define MS_ABI_PRELUDE_H

#include "base/safe.h"

MS_UNUSED static const char *const MS_PRIMITIVE_TYPES[] = {"Bool",   "Int",    "Float",   "Int8",    "Int16",   "Int32",
                                                           "Int64",  "UInt8",  "UInt16",  "UInt32",  "UInt64",  "Float32",
                                                           "Float64", "String", "Void",    "Never"};
MS_UNUSED static const char *const MS_PRELUDE_TYPES[] = {"Equal", "Stringable", "Comparable", "Hashable", "Clonable",
                                                         "Optional", "Result", "Error", "List", "Map", "Set",
                                                         "ListEntry", "MapEntry"};

#define MS_PRIMITIVE_TYPE_COUNT (sizeof MS_PRIMITIVE_TYPES / sizeof MS_PRIMITIVE_TYPES[0])
#define MS_PRELUDE_TYPE_COUNT (sizeof MS_PRELUDE_TYPES / sizeof MS_PRELUDE_TYPES[0])

/* Whether `name` is one of the prelude's own type names (not a primitive). */
MS_UNUSED static inline bool ms_is_prelude_type(MsSpan name) {
  for (size_t i = 0; i < MS_PRELUDE_TYPE_COUNT; i++) {
    if (ms_span_is_text(name, MS_PRELUDE_TYPES[i])) {
      return true;
    }
  }
  return false;
}

#endif
