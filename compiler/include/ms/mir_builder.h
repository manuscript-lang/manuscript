/* libms MIR builder: builds one function inside a module, with optional SSA variables. A port of
 * crates/ms-mir/src/builder.rs (the part the optimiser's generated functions need; lowering adds
 * the typed helpers it wants). Mutable source variables are modelled with `MirVar`s
 * (`mir_b_declare_var`, `mir_b_def_var`, `mir_b_use_var`, `mir_b_seal_block`), which the builder
 * turns into block parameters (Braun et al., Simple and Efficient Construction of SSA Form). The
 * builder never inserts clones or drops: ownership is the caller's job and the verifier checks it.
 *
 * No global state. The builder keeps its scratch tables in its own arena; the function it builds
 * lives in the module's arena. Every `MirBuilder` ends with `mir_b_finish`. */
#ifndef MS_MIR_BUILDER_H
#define MS_MIR_BUILDER_H

#include "ms/mir.h"
#include "ms_rt/safe.h"

typedef uint32_t MirVar;

typedef struct MirVarInfo {
    MirTy ty;
    uint8_t mode;
    bool single;        /* defined exactly once, read only where that definition dominates */
    MirValue only_def;  /* the one definition of a single variable, or MIR_NONE */
} MirVarInfo;

/* One `(variable, block)` definition. */
typedef struct MirVarDef {
    MirVar var;
    MirBlock block;
    MirValue value;
    bool used; /* the slot is taken */
} MirVarDef;

/* The scratch lists a block carries during construction. */
typedef struct MirBlockLinks {
    MirBlock *preds; /* every edge, with repeats */
    uint32_t npreds, cpreds;
    bool sealed;
    MirVar *waiting_var; /* block parameters waiting for the block to be sealed */
    MirValue *waiting_param;
    uint32_t nwaiting, cwaiting;
} MirBlockLinks;

typedef struct MirBuilder {
    MirModule *m;
    MirFunc f;
    MirBlock cur;
    MirLoc loc;
    MsArena scratch;
    MirVarInfo *vars;
    uint32_t nvars, cvars;
    MirVarDef *defs; /* open-addressed hash of (variable, block) */
    uint32_t ndefs, cdefs;
    MirBlockLinks *links; /* by block */
    uint32_t clinks;
    MirValue *forward; /* by value: the value a removed trivial parameter stands for */
    uint32_t cforward;
    uint32_t depth;
    bool failed; /* a read recursed too deep; the function is not usable */
} MirBuilder;

/* Starts a function; the entry block is current and sealed. */
void mir_b_init(MirBuilder *b, MirModule *m, MsSym name, const MirParam *params, uint32_t nparams,
                MirTy ret);
/* A generated fast path: an internal function marked `inline(always)`. */
void mir_b_init_fast_path(MirBuilder *b, MirModule *m, MsSym name, const MirParam *params,
                          uint32_t nparams, MirTy ret);
/* Finishes without adding the function to the module: copies it to `out` with edge arguments
 * naming removed parameters replaced, and frees the scratch tables. False when the build failed. */
MS_NODISCARD bool mir_b_into_func(MirBuilder *b, MirFunc *out);
/* Finishes and adds the function to the module; `*id` is its index. */
MS_NODISCARD bool mir_b_finish(MirBuilder *b, uint32_t *id);

static inline MirFunc *mir_b_func(MirBuilder *b) { return &b->f; }
static inline MirTy mir_b_ty(const MirBuilder *b, MirValue v) { return mir_value_ty(&b->f, v); }
static inline MirBlock mir_b_current(const MirBuilder *b) { return b->cur; }
/* Opens a debugger scope for code that runs in another function's frame but is emitted here (a
 * default argument): fault traces show `name` called from `call_line`. Every position set after
 * it carries the scope (`MirLoc.scope`). Returns the scope to give `mir_b_close_scope`. */
uint32_t mir_b_open_scope(MirBuilder *b, MsSym name, uint32_t file, uint32_t call_line);
/* Returns to the scope `mir_b_open_scope` returned. */
void mir_b_close_scope(MirBuilder *b, uint32_t outer);

static inline void mir_b_set_loc(MirBuilder *b, MirLoc loc) { b->loc = loc; }
static inline void mir_b_switch_to(MirBuilder *b, MirBlock block) { b->cur = block; }
/* The entry block's parameter values: `n` of them are written to `out`. */
void mir_b_params(const MirBuilder *b, MirValue *out, uint32_t n);

MirBlock mir_b_new_block(MirBuilder *b); /* starts unsealed */
MirValue mir_b_add_block_param(MirBuilder *b, MirBlock block, MirTy ty, MirMode mode);

/* Emits an instruction; `res_ty` is MIR_NONE for one without a result. Returns the result value,
 * or MIR_NONE. */
MirValue mir_b_emit(MirBuilder *b, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirTy res_ty);

MirValue mir_b_iconst(MirBuilder *b, int64_t v);
MirValue mir_b_bconst(MirBuilder *b, bool v);
MirValue mir_b_unit(MirBuilder *b);
MirValue mir_b_binop(MirBuilder *b, MirOp op, MirValue a, MirValue c); /* typed like `a` */
/* `icmp`; an ordered comparison of `UInt64` operands is the unsigned `uicmp`. */
MirValue mir_b_icmp(MirBuilder *b, MirCc cc, MirValue a, MirValue c);
MirValue mir_b_select(MirBuilder *b, MirValue cond, MirValue a, MirValue c);
MirValue mir_b_list_new(MirBuilder *b, MirTy elem, MirValue cap);
/* `call` a module function; a borrowing variant passed where its ordinary alternative is
 * expected is read as one (`alt.plain`). */
MirValue mir_b_call(MirBuilder *b, uint32_t func, const MirValue *args, uint32_t nargs);
MirValue mir_b_call_rt(MirBuilder *b, uint32_t ext, const MirValue *args, uint32_t nargs);

/* Terminators of the current block. */
void mir_b_br(MirBuilder *b, MirBlock to, const MirValue *args, uint32_t nargs);
void mir_b_br_if(MirBuilder *b, MirValue cond, MirBlock then, const MirValue *then_args,
                 uint32_t nthen, MirBlock els, const MirValue *els_args, uint32_t nels);
void mir_b_switch(MirBuilder *b, MirValue value, const MirCase *cases, uint32_t ncases,
                  MirBlock fallback);
void mir_b_ret(MirBuilder *b, MirValue value); /* MIR_NONE returns nothing */
void mir_b_fault(MirBuilder *b, MirFault kind);
void mir_b_unreachable(MirBuilder *b);

/* Variables. */
MirVar mir_b_declare_var(MirBuilder *b, MirTy ty, MirMode mode);
/* A variable defined once and read only where that definition dominates (an immutable `let`). */
MirVar mir_b_declare_single(MirBuilder *b, MirTy ty, MirMode mode);
void mir_b_def_var(MirBuilder *b, MirVar var, MirValue value); /* at the end of the current block */
MirValue mir_b_use_var(MirBuilder *b, MirVar var);               /* in the current block */
/* Declares that every predecessor of `block` has been emitted. */
void mir_b_seal_block(MirBuilder *b, MirBlock block);

#endif
