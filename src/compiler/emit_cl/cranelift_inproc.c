/* Owns loading the Cranelift library and filling the function table (see cranelift_inproc.h). */
#define CL_DEFINE_API
#include "compiler/emit_cl/cranelift_inproc.h"

#include "base/dylib.h"

#include <stdatomic.h>

static void *resolve(void *library, const char *name) {
  return ms_dylib_symbol(library, name);
}

bool cranelift_load(MsSpan path, MsStrBuild *why) {
  static atomic_bool ready;
  if (atomic_load(&ready)) {
    return true;
  }
  static MsDylib library; /* stays loaded: the process compiles one program */
  if (!ms_dylib_open(path, &library, why)) {
    return false;
  }
  const char *missing = cl_bind(resolve, &library);
  if (missing != NULL) {
    ms_strbuild_append_text(why, "the Cranelift library lacks ");
    ms_strbuild_append_text(why, missing);
    return false;
  }
  atomic_store(&ready, true);
  return true;
}

bool cranelift_usable(MsSpan path) {
  MsStrBuild why = ms_strbuild_new();
  const bool usable = cranelift_load(path, &why);
  ms_strbuild_free(&why);
  return usable;
}
