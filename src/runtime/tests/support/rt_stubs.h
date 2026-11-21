/* Control of the faults the stubs in rt_stubs.c raise. */
#ifndef MS_TEST_RT_STUBS_H
#define MS_TEST_RT_STUBS_H

#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>

/* When set, a fault jumps here instead of aborting; its message and family are recorded below. */
extern jmp_buf *ms_test_fault;
extern char ms_test_fault_message[256];
extern uint8_t ms_test_fault_kind;
/* Cleanups pushed and not yet discarded. */
extern size_t ms_test_cleanups;

#endif
