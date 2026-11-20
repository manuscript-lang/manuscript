/* What the Rust runtime provides to runtime/core in a real build, stubbed for the C unit tests. */
#ifndef MS_TEST_RT_STUBS_H
#define MS_TEST_RT_STUBS_H
#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>

/* When set, msrt_fault jumps here instead of aborting; the message is copied to ms_test_fault_msg. */
extern jmp_buf *ms_test_fault;
extern char ms_test_fault_msg[256];
#endif
