/* Internal definitions shared by mir_val.c, mir_interp_ops.c and mir_interp.c. */
#ifndef MS_MIR_INTERP_IMPL_H
#define MS_MIR_INTERP_IMPL_H

#include "ms/mir_interp.h"

/* A reference-counted aggregate: `count` values (or bytes, for a string) in `items`. */
struct MirBlob {
    uint32_t refs;
    uint32_t count;
    uint32_t cap; /* items or bytes that fit */
    MirVal items[];
};

typedef struct IpHost {
    char *name; /* owned by the interpreter arena */
    MirHostFn fn;
    void *context;
} IpHost;

typedef struct IpCleanup {
    uint32_t closer;
    MirVal value; /* owned */
} IpCleanup;

/* The error being raised: what the program will see if nothing catches it. */
typedef struct IpRaw {
    MirFault kind;
    MsStr message; /* in the interpreter arena */
    bool fuel;
} IpRaw;

struct MirInterp {
    const MirModule *module; /* borrowed from the caller */
    MsArena arena;           /* owned: texts of faults and host names */
    MirVal *strings;         /* owned: one value per string literal of the module */
    uint32_t nstrings;
    MirVal *globals;         /* owned: one value per global */
    MirVal *memory;          /* owned: the stack slots, address = index + 1 */
    uint32_t nmemory, cmemory;
    IpCleanup *cleanup;      /* owned: pending cleanup actions, innermost last */
    uint32_t ncleanup, ccleanup;
    uint8_t *drop_cache;     /* owned: by type, 0 unknown, 1 plain, 2 needs a drop */
    IpHost *hosts;           /* owned */
    uint32_t nhosts, chosts;
    MirVal *call_args;       /* owned: arguments of the call being made */
    uint32_t ncall_args, ccall_args;
    uint32_t callee;
    MirVal dummy;            /* stands in for an operand the instruction does not have */
    int64_t depth;
    uint64_t steps, fuel, drops;
    uint32_t exec_depth;
    bool unwinding, cancelled;
    MsBuf out;
    IpRaw raw;
    MirInterpFault fault;
};

typedef enum IpFlow { IP_NEXT, IP_CALL, IP_RAISE, IP_DONE } IpFlow;

/* One instruction being executed. */
typedef struct IpCtx {
    MirInterp *it;
    const MirFunc *func;
    MirVal *regs; /* the frame's registers */
    const MirInst *inst;
} IpCtx;

/* ---- values (mir_val.c) ---- */
/* Allocation failure ends the process, as everywhere in libms. */
MS_NORETURN void ip_oom(void);
void *ip_regrow(void *old, size_t old_bytes, size_t new_bytes);
MirVal ip_retain(MirVal value);
MirVal ip_void(void);
MirVal ip_float(double value);
MirVal ip_ptr(uint64_t address);
MirBlob *ip_blob_new(uint32_t count); /* items void; null for none */
MirVal ip_aggregate(uint8_t tag, uint32_t id, MirBlob *blob);
/* Runs the runtime's map function `name` when it is one: true with `*result` set, or `*flow` raised. */
bool ip_map_runtime(MirInterp *it, MsStr name, const MirVal *args, uint32_t count, MirVal *result, IpFlow *flow);
MirVal ip_str(const char *bytes, size_t length);
MsStr ip_str_view(MirVal value);
MirVal ip_opt_some(MirVal payload); /* takes the payload */
uint32_t ip_count(MirVal value);
MirVal *ip_items(MirVal value); /* null when empty */
/* Makes the aggregate's block exclusively owned (copying it when shared); false if not an aggregate. */
bool ip_make_unique(MirVal *value);
void ip_list_push(MirVal *list, MirVal item); /* list is exclusively owned */
void ip_list_pop(MirVal *list);
void ip_show(MsBuf *out, MirVal value);
void ip_fmt_float(MsBuf *out, double value);

/* ---- instruction semantics (mir_interp_ops.c) ---- */
MirVal ip_default_val(const MirInterp *it, MirTy ty, uint32_t depth);
IpFlow ip_step(MirInterp *it, const MirFunc *func, MirVal *regs, const MirInst *inst);
IpFlow ip_raise(MirInterp *it, MirFault kind, const char *fmt, ...) MS_PRINTF(3, 4);
IpFlow ip_internal(MirInterp *it, const char *fmt, ...) MS_PRINTF(2, 3);
bool ip_exec(MirInterp *it, uint32_t entry, MirVal *args, uint32_t nargs, MirVal *result);
MirVal ip_take_arg(MirInterp *it, const MirFunc *func, MirVal *regs, uint32_t value, bool own);
/* Nested interpreter runs (cleanup actions raising cleanup actions); bounds the C stack. */
#define IP_MAX_EXEC_DEPTH 2000
const char *ip_depth_message(void);
uint32_t ip_grow_cap(uint32_t count, uint32_t first);
IpFlow ip_raise_text(MirInterp *it, MirFault kind, MsStr message);
/* Makes room for `count` staged arguments (all void) and returns them. */
MirVal *ip_stage(MirInterp *it, uint32_t count);

#endif
