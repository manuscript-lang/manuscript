#ifndef MS_RUNTIME_CORE_FAULT_KEPT_H
#define MS_RUNTIME_CORE_FAULT_KEPT_H

#include <stddef.h>
#include <stdint.h>

#include "runtime/core/fault.h"

/* The promise table calls this when a task that ran under a test output capture ended with a fault; the test runner
 * takes the record with ms_test_take_fault. */
void ms_test_keep_fault(uint64_t capture, const MsFaultText *text);
/* Ending a capture drops the record nobody took. */
void ms_test_drop_fault(uint64_t capture);
/* Hands the caller the encoded record of the last fault under `capture` (NULL and 0 when none); the caller frees it. */
void ms_test_take_fault(uint64_t capture, uint8_t **bytes, size_t *length);

#endif
