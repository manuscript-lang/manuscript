/* compiler/check/hooks.h: the methods lowering calls on a value without the source naming them.
 *
 * Closing a binding, hashing a map key, showing a value in text, encoding it as JSON, iterating it, applying an
 * operator to records and running a test fixture's hooks all look a method up by name on the value's type. A
 * bundled standard method no checked body names but one of these reaches is still needed, so the lazy standard
 * checker (lazy_std.c) restores these methods for every type a checked body mentions, and lowering looks up
 * a method through `lower_named_method(cx, type, MsHook)`, so a lookup of a name not in this table does not compile. */
#ifndef MS_COMPILER_CHECK_HOOKS_H
#define MS_COMPILER_CHECK_HOOKS_H

#include <stdbool.h>

/* One entry per method lowering may call on a value: the enumerator and the method's name. */
#define MS_HOOK_METHODS(X)                                                                                         \
  X(CLOSE, "close") X(CLONE, "clone") X(EQUALS, "equals") X(HASH, "hash") X(COMPARE, "compare")                  \
  X(TO_STRING, "to_string") X(TO_JSON, "to_json") X(ENTRIES, "entries") X(VALUES, "values") X(NEXT, "next")      \
  X(ADD, "add") X(SUBTRACT, "subtract") X(MULTIPLY, "multiply") X(DIVIDE, "divide") X(REMAINDER, "remainder")    \
  X(BEFORE_ALL, "before_all") X(BEFORE_EACH, "before_each") X(AFTER_EACH, "after_each") X(AFTER_ALL, "after_all")

typedef enum MsHook {
#define MS_HOOK_ENUM(id, text) MS_HOOK_##id,
  MS_HOOK_METHODS(MS_HOOK_ENUM)
#undef MS_HOOK_ENUM
  MS_HOOK_COUNT
} MsHook;

static inline const char *ms_hook_name(MsHook hook) {
  static const char *const names[MS_HOOK_COUNT] = {
#define MS_HOOK_TEXT(id, text) text,
      MS_HOOK_METHODS(MS_HOOK_TEXT)
#undef MS_HOOK_TEXT
  };
  return names[hook];
}

/* The bundled functions lowering calls itself, found by name: the builder of an `Error` from a failed status, and
 * the drivers of a test or bench run. They are restored whenever their module is loaded. */
#define MS_ROOT_FUNCTIONS(X)                                                                                       \
  X("msstd_status_error") X("status_error_text") X("run_fixture_file") X("run_plain_file") X("run_test_files")  \
  X("run_bench_block") X("run_bench_fixture")

#endif
