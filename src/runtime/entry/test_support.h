/* entry/test_support.h: what the test runner (stdlib/internal/test_runner.ms) asks of the runtime besides the output
 * captures of io/stdout.h: bounding a test's waits, appending its result records and reporting a failed expectation. */
#ifndef MS_RUNTIME_ENTRY_TEST_SUPPORT_H
#define MS_RUNTIME_ENTRY_TEST_SUPPORT_H

#include <stdbool.h>

#include "base/map.h"
#include "base/string.h"

/* Bounds the waits of the running task by the MS_TEST_TIMEOUT_NS of the environment while `on`; `on` false lifts it. */
/* ms-sig: msrt_test_deadline(on: bool) */
void msrt_test_deadline(bool on);

/* Appends `text` to the file at `path` in one write, so records of tests running at once never interleave, and rings
 * the bell the supervisor named. Failure is ignored: the supervisor reports the test as unfinished. */
/* ms-sig: msrt_test_record(path: *const StrVal, text: *const StrVal) */
void msrt_test_record(const MsString *path, const MsString *text);

/* Reports a failed expectation: the message and its `site` detail on standard error, and a fault record. */
/* ms-sig: msrt_test_failure(message: *const StrVal, details: *const MapVal) */
void msrt_test_failure(const MsString *message, const MsMap *details);

#endif
