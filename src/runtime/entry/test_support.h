/* entry/test_support.h: what the test runner (src/stdlib/internal/test_runner.ms) asks of the runtime besides the
 * output captures of io/stdout.h: bounding a test's waits, appending its result records and reporting a
 * failed expectation. */
#ifndef MS_RUNTIME_ENTRY_TEST_SUPPORT_H
#define MS_RUNTIME_ENTRY_TEST_SUPPORT_H

#include "abi/shape.h"
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

/* Takes a bench body's last value so the work that computed it cannot be removed: the call is to a function the
 * compiler does not see into, and the value is read through its shape table's address. */
/* ms-sig: msstd_bench_sink(shape: *const ShapeTable, value: *const u8) @domain=test @end */
void msstd_bench_sink(const MsShapeTable *table, const void *value);

#endif
