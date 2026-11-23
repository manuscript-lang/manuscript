/* The shared-library loading of base/dylib.h, on libuv's uv_dlopen (dlopen on Linux and macOS, LoadLibraryEx on
 * Windows). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/dylib.h"

#include <uv.h>

#include "base/alloc.h"
#include "base/ostext.h"
#include "base/path.h"

bool ms_dylib_open(MsSpan path, MsDylib *out, MsStrBuild *why) {
  if (!ms_path_is_absolute(path)) {
    ms_strbuild_append_text(why, "the library path is not absolute: ");
    ms_strbuild_append(why, path);
    return false;
  }
  uv_lib_t *library = ms_alloc_zeroed(sizeof(*library));
  MsOsText name = ms_os_text_new(path);
  const bool ok = uv_dlopen(name.ptr, library) == 0;
  ms_os_text_free(&name);
  if (!ok) {
    ms_strbuild_append_text(why, "cannot load ");
    ms_strbuild_append(why, path);
    ms_strbuild_append_text(why, ": ");
    ms_strbuild_append_text(why, uv_dlerror(library));
    uv_dlclose(library);
    ms_free(library);
    return false;
  }
  out->handle = library;
  return true;
}

void *ms_dylib_symbol(const MsDylib *library, const char *name) {
  void *address = NULL;
  if (library->handle == NULL || uv_dlsym((uv_lib_t *)library->handle, name, &address) != 0) {
    return NULL;
  }
  return address;
}

void ms_dylib_close(MsDylib *library) {
  if (library->handle != NULL) {
    uv_dlclose((uv_lib_t *)library->handle);
    ms_free(library->handle);
    library->handle = NULL;
  }
}
