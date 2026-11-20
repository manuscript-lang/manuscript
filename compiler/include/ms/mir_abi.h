/* Constants of the running-task layout that generated code reads directly. Equal to the
 * `ms_rt_abi::symbols` constants of the runtime (crates/ms-rt-abi/src/lib.rs). */
#ifndef MS_MIR_ABI_H
#define MS_MIR_ABI_H

/* Size and alignment of a stack region; every task stack lies inside one. */
#define MIR_STACK_REGION ((int64_t)256 << 20)
/* Distance from the end of a stack region to the word holding the running stack segment's
 * recursion limit. */
#define MIR_STACK_LIMIT_CELL 8

#endif
