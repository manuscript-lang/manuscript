/* base/dylib.h: loading a shared library by absolute path and finding its functions, on libuv.
 *
 * The path is never searched for: a relative path or a bare name is refused, so a library elsewhere on the machine
 * can never be picked up in place of the pinned one.
 *
 * Ownership: an MsDylib owns the loaded library and ends with ms_dylib_close. */
#ifndef MS_BASE_DYLIB_H
#define MS_BASE_DYLIB_H

#include "base/strbuild.h"

typedef struct MsDylib {
  void *handle; /* the library, NULL when none is loaded */
} MsDylib;

/* Loads the library at `path`. On failure `why` gets the system's reason and `out` is left as it was. */
MS_NODISCARD MS_NONNULL bool ms_dylib_open(MsSpan path, MsDylib *out, MsStrBuild *why);

/* The address of the function or object `name` (a C symbol), or NULL when the library does not export it. */
void *ms_dylib_symbol(const MsDylib *library, const char *name);

/* Unloads the library; its symbols must not be used afterwards. A library that is not open is left alone. */
void ms_dylib_close(MsDylib *library);

#endif
