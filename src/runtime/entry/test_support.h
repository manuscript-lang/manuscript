/* entry/test_support.h: what the test runner (stdlib/internal/test_runner.ms) asks of the runtime besides the
 * output captures of io/stdout.h: bounding a test's waits, appending its result records and reporting a
 * failed expectation. */
#ifndef MS_RUNTIME_ENTRY_TEST_SUPPORT_H
#define MS_RUNTIME_ENTRY_TEST_SUPPORT_H

#include <stdbool.h>

#include "base/map.h"
#include "base/string.h"

/* Bounds the waits of the running task by the MS_TEST_TIMEOUT_NS of the environment while `on`; `on` false
 * lifts it. */
/* ms-sig: msrt_test_deadline(on: bool) */
void msrt_test_deadline(bool on);

/* Appends `text` to the file at `path` in one write, so records of tests running at once never interleave,
 * and rings the bell the supervisor named. Failure is ignored: the supervisor reports the test as unfinished.
 */
/* ms-sig: msrt_test_record(path: *const StrVal, text: *const StrVal) */
void msrt_test_record(const MsString *path, const MsString *text);

/* Hands over the encoded fault record of the last task under capture `id` that faulted ("" when none); taking
 * it clears it. */
/* ms-sig: msrt_test_capture_fault(id: i64, out: *mut StrVal) */
void msrt_test_capture_fault(int64_t id, MsString *out);

/* Reports a failed expectation: the message and its `site` detail on standard error, and a fault record. */
/* ms-sig: msrt_test_failure(message: *const StrVal, details: *const MapVal) */
void msrt_test_failure(const MsString *message, const MsMap *details);

/* Takes a bench's result so the work that computed it cannot be removed or folded into a constant: the call is to a
 * function the compiler does not see into, and `value` is stored where it may be read. */
/* ms-sig: msrt_bench_keep(value: i64) */
void msrt_bench_keep(int64_t value);

/* Returns `value`, through a function the compiler does not see into, so a bench's input is not known when it is
 * compiled and the work over it is not folded away. */
/* ms-sig: msrt_bench_opaque(value: i64) -> i64 */
int64_t msrt_bench_opaque(int64_t value);

#endif
