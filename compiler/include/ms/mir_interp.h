/* MIR interpreter: the reference semantics of the IR (port of crates/ms-mir interp.rs), the
 * oracle the optimiser and the native back ends are checked against. It models values itself and
 * needs no runtime. Slow by design: it is for tests and for `--interp` style tools.
 *
 * Decisions (as in the Rust version):
 *  - `type.set`, `list.set*` and `list.push` consume their collection operand and yield the
 *    updated value. Negative indices of `list.get` and `list.set` count from the end; the `.nn`
 *    forms fault on negative indices. The `.u` forms fault like the checked ones.
 *  - `f2i.opt` yields none for NaN, infinities and values outside the Int range.
 *  - `sdiv.chk` faults on zero (DivByZero) and on MIN / -1 (IntOverflow); `srem.chk` faults on
 *    zero and yields 0 for MIN % -1. The unchecked forms wrap and still fault on zero.
 *  - `shl` and `sshr` use the low six bits of the shift amount.
 *  - `cleanup.push` yields a handle; `cleanup.run` pops and runs the innermost action. A fault
 *    runs the remaining actions last in first out; faults inside them are collected.
 *  - `call.rt` looks the symbol up among the registered host functions. Built in: msrt_fault,
 *    msrt_print_int, msrt_print_float, msrt_print_bool, msrt_print_str, msrt_exit_frees,
 *    msrt_shield_enter, msrt_shield_exit, msrt_unwinding.
 *  - The owned shorthands (`alt.own`, `alt.unbox`, `alt.release`, `type.release`, `opt.unbox`,
 *    `opt.unwrap`) must have been expanded already; the C expansion is not ported yet, so a
 *    module that still has them stops with an internal fault.
 *
 * Aggregates are reference counted with copy on write: borrowing an operand is cheap, and a
 * consuming op mutates in place when it holds the only reference. Counts are not atomic; one
 * interpreter belongs to one thread. */
#ifndef MS_MIR_INTERP_H
#define MS_MIR_INTERP_H

#include "ms/mir.h"
#include "ms_rt/safe.h"

/* Calls nest this deep (`depth.enter`), and no more than MIR_INTERP_MAX_FRAMES frames are live. */
#define MIR_INTERP_MAX_CALL_DEPTH 200000
#define MIR_INTERP_MAX_FRAMES 2000000

typedef enum MirValTag {
    MV_VOID, MV_BOOL, MV_INT, MV_FLOAT, MV_STR, MV_PTR, MV_TYPE, MV_ALT, MV_LIST, MV_OPT,
    MV_CLOSURE, MV_IFACE, MV_MAP
} MirValTag;

typedef struct MirBlob MirBlob;

/* An interpreter value. `blob` is owned (counted) for the aggregate tags (a map's blob holds its keys
 * and values alternately, in insertion order); `id` is the case of an
 * alternative, the function of a closure, the vtable of an interface value. */
typedef struct MirVal {
    uint8_t tag;
    uint32_t id;
    union {
        int64_t i; /* MV_BOOL, MV_INT */
        double f;  /* MV_FLOAT */
        uint64_t p; /* MV_PTR */
        MirBlob *blob; /* null is an empty aggregate, an empty string or none */
    } as;
} MirVal;

MirVal mir_val_int(int64_t value);
MirVal mir_val_bool(bool value);
/* Gives up one reference and leaves the value void. */
void mir_val_release(MirVal *value);

/* A program fault: the interpreter's analogue of the native fault protocol. Texts live as long as
 * the interpreter. */
typedef struct MirInterpFault {
    MirFault kind;
    MsStr message;
    const MsStr *stack; /* frames, innermost first, as `function (file:line)` */
    uint32_t nstack;
    const MsStr *cleanup_faults; /* messages of faults raised by cleanup actions while unwinding */
    uint32_t ncleanup_faults;
    bool fuel_exhausted;
} MirInterpFault;

/* A host implementation of a runtime function. It appends to `out` (the program's standard
 * output) and stores its result. Returning false raises a fault with `*error` as its message. */
typedef bool (*MirHostFn)(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                          MirVal *result, MsStr *error);

typedef struct MirInterp MirInterp;

/* An interpreter for `module`, which must outlive it and not change. Owned: free it with
 * mir_interp_free. */
MirInterp *mir_interp_new(const MirModule *module);
void mir_interp_free(MirInterp *interp);

/* Registers (or replaces) the host function called `name`; the name is copied. */
void mir_interp_register(MirInterp *interp, const char *name, MirHostFn fn, void *context);
/* Limits the number of executed instructions and terminators; 0 is no limit. */
void mir_interp_set_fuel(MirInterp *interp, uint64_t fuel);
/* The flag `poll` checks; once set the next poll faults. */
void mir_interp_set_cancel(MirInterp *interp, bool cancelled);

/* Everything the program printed. Borrowed, valid until the next run. */
MsStr mir_interp_stdout(const MirInterp *interp);
uint64_t mir_interp_drops(const MirInterp *interp);
uint64_t mir_interp_steps(const MirInterp *interp);

/* Runs the entry function. False means a fault: read it with mir_interp_fault. */
MS_NODISCARD bool mir_interp_run_entry(MirInterp *interp, int64_t *exit_code);
/* Calls function `func` with `nargs` owned arguments (it takes them). On success `*result` is
 * owned by the caller. */
MS_NODISCARD bool mir_interp_call(MirInterp *interp, uint32_t func, MirVal *args,
                                       uint32_t nargs, MirVal *result);
/* The fault of the last failed run. */
const MirInterpFault *mir_interp_fault(const MirInterp *interp);

#endif
