/* ms_rt/test.h: what the test runner (@std/internal/test_runner) calls (src/runtime/entry/test_support.c). Symbols are listed in
 * src/runtime/symbols/test.txt. */
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

/* The output captures of a test run (src/runtime/core/stdout.c): what the tasks of one test print is kept apart. */
/* ms-sig: msrt_test_capture_new() -> i64 */
int64_t msrt_test_capture_new(void);

/* ms-sig: msrt_test_capture_set(id: i64) */
void msrt_test_capture_set(int64_t id);

/* ms-sig: msrt_test_capture_current() -> i64 */
int64_t msrt_test_capture_current(void);

/* ms-sig: msrt_test_capture_take(id: i64, out: *mut StrVal) */
void msrt_test_capture_take(int64_t id, MsStr *out_text);

/* ms-sig: msrt_test_capture_free(id: i64) */
void msrt_test_capture_free(int64_t id);

#endif
