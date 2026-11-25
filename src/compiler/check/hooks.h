/* compiler/check/hooks.h: the methods lowering calls on a value without the source naming them.
 *
 * Closing a binding, hashing a map key, showing a value in text, encoding it as JSON, iterating it, applying an
 * operator to records and running a test fixture's hooks all look a method up by name on the value's type. A
 * bundled standard method no checked body names but one of these reaches is still needed, so the lazy standard
 * checker (lazy_std.c) restores these methods for every type a checked body mentions, and lowering looks up
 * only these names (`lower_named_method` faults on any other). A new hook is added here and nowhere else. */
#ifndef MS_COMPILER_CHECK_HOOKS_H
#define MS_COMPILER_CHECK_HOOKS_H

#include <stdbool.h>
#include "base/cstr.h"

#define MS_HOOK_METHODS(X)                                                                                         \
  X("close") X("clone") X("equals") X("hash") X("compare") X("to_string") X("to_json") X("entries") X("values") X("next")   \
  X("add") X("subtract") X("multiply") X("divide") X("remainder")                                                 \
  X("before_all") X("before_each") X("after_each") X("after_all")

/* The bundled functions lowering calls itself, found by name: the builder of an `Error` from a failed status, and
 * the drivers of a test or bench run. They are restored whenever their module is loaded. */
#define MS_ROOT_FUNCTIONS(X)                                                                                       \
  X("msstd_status_error") X("status_error_text") X("run_fixture_file") X("run_plain_file") X("run_test_files")  \
  X("run_bench_block") X("run_bench_fixture")

static inline bool ms_is_hook_method(const char *name) {
#define MS_HOOK_IS(text) if (ms_cstr_equal(name, text)) return true;
  MS_HOOK_METHODS(MS_HOOK_IS)
#undef MS_HOOK_IS
  return false;
}

#endif
