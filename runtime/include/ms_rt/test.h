/* ms_rt/test.h: what the test runner (@std/internal/test_runner) calls (runtime/entry/test_support.c). The output
 * captures it also uses are declared with the standard output they redirect. Symbols are listed in
 * runtime/symbols/test.txt. */
/* ms: domain test */
#ifndef MS_RT_TEST_H
#define MS_RT_TEST_H

#include <stdbool.h>

#include "ms_rt/map.h"
#include "ms_rt/string.h"

/* ms-sig: msrt_test_deadline(on: bool) */
void msrt_test_deadline(bool on);

/* ms-sig: msrt_test_record(path: *const StrVal, text: *const StrVal) */
void msrt_test_record(const MsStr *path, const MsStr *text);

/* ms-sig: msrt_test_failure(message: *const StrVal, details: *const MapVal) */
void msrt_test_failure(const MsStr *message, const MsMap *details);

/* ms-sig: msrt_test_capture_fault(id: i64, out: *mut StrVal) */
void msrt_test_capture_fault(int64_t id, MsStr *out);

#endif
