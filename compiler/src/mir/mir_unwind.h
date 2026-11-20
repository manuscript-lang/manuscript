/* unwind: the state and helpers its source files share (mir_unwind_*.c). Port of unwind.rs. */
#ifndef MS_MIR_UNWIND_H
#define MS_MIR_UNWIND_H

#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"
#include "ms/mir_pass.h"
#include "ms/mir_persist.h"

/* A hash map from `uint64_t` to `uint64_t`; as a set the values are unused. The zero value is
 * empty; storage comes from the arena each update is given. */
typedef struct UwHash {
    uint64_t *key, *val;
    uint8_t *used;
    uint32_t cap, n;
} UwHash;

bool uh_get(const UwHash *h, uint64_t k, uint64_t *v); /* `v` may be NULL */
static inline bool uh_has(const UwHash *h, uint64_t k) { return uh_get(h, k, NULL); }
bool uh_put(MsArena *a, UwHash *h, uint64_t k, uint64_t v); /* whether `k` was new */
bool uh_del(UwHash *h, uint64_t k);
UwHash uh_clone(MsArena *a, const UwHash *h);
uint64_t *uh_keys(MsArena *a, const UwHash *h); /* ascending, `h->n` of them */
bool uh_equal_sets(const UwHash *x, const UwHash *y);

/* Per function and parameter: a flag. Rows exist only for the functions that existed when the
 * table was made. */
typedef struct UwTable {
    bool **v;
    uint32_t *len;
    uint32_t n;
} UwTable;

static inline bool uw_flag(const UwTable *t, uint32_t f, uint32_t k) {
    return f < t->n && k < t->len[f] && t->v[f][k];
}

typedef struct UwCx {
    MirModule *m;
    MsArena pass; /* everything that outlives a function */
    MsArena fn;   /* reset after each function */
    bool *parks, *faults;
    uint32_t nfuncs0; /* the functions that existed when the pass began: the length of `parks` */
    UwTable safe, owns, pointer;
    uint32_t *targets; /* the functions a `closure.new` makes callable, ascending */
    uint32_t ntargets;
    uint32_t discard;
    UwHash cells;    /* slot -> the type it holds */
    UwHash closers, with_closers, slot_droppers, raw_closers, partial_closers, box_closers;
    UwHash raw_values;
    UwHash box_values; /* method receivers the function then forgets: a `move` receiver, whose payload the callee took */
    UwHash holes;    /* (owner << 32 | field) -> its stand-in value */
    UwHash partials; /* stand-in -> (owner << 32 | field) */
    UwHash proj;     /* projection result -> (owner << 32 | field) */
} UwCx;

#define UW_INSTS(f, b_, i_, inst_)                                                                 \
    for (uint32_t(b_) = 0; (b_) < (f)->nblocks; (b_)++)                                            \
        for (uint32_t(i_) = 0; (i_) < (f)->blocks[(b_)].ninsts; (i_)++)                            \
            for (const MirInst *(inst_) = &(f)->blocks[(b_)].insts[(i_)]; (inst_) != NULL;         \
                 (inst_) = NULL)

static inline MirValue uw_arg(const MirInst *inst, uint32_t k) {
    return k < inst->nargs ? inst->args[k] : MIR_NONE;
}
static inline bool uw_is_func(const MirInst *inst, MirOp op, uint32_t *g) {
    if (inst->op != op || inst->imm.tag != MI_FUNC) {
        return false;
    }
    *g = inst->imm.a;
    return true;
}

/* ---- mir_unwind_slots.c ---- */
bool uw_takes_from_slot_in(const MirModule *m, uint32_t callee, UwHash *memo, MsArena *ma);
UwTable uw_slot_safe_params(MsArena *a, const MirModule *m);
bool uw_closure_borrows_capture(const MirModule *m, const UwTable *safe, const bool *parks,
                                uint32_t g, uint32_t idx);
UwTable uw_slot_owned_params(MsArena *a, const MirModule *m, const UwTable *safe);
uint32_t *uw_closure_targets(MsArena *a, const MirModule *m, uint32_t *n);
void uw_find_cells(UwCx *cx, const MirFunc *f, const UwHash *params);
bool uw_hands_off(const UwCx *cx, const MirInst *inst, uint32_t k);
UwHash uw_covered_slot_takes(MsArena *a, const MirModule *m, const MirFunc *f, bool borrowed_only);
bool uw_slot_close_value(const MirModule *m, uint32_t close, MirTy *ty);
bool uw_ext_named(const MirModule *m, const MirInst *inst, const char *name);

/* ---- mir_unwind_closers.c ---- */
uint32_t uw_raw_closer(UwCx *cx, MirTy ty);
uint32_t uw_box_closer(UwCx *cx, MirTy ty);
uint32_t uw_partial_closer(UwCx *cx, MirTy ty, uint32_t r, uint32_t field);
uint32_t uw_closer(UwCx *cx, MirTy ty);
uint32_t uw_slot_dropper(UwCx *cx, MirTy ty);
void uw_name_holes(UwCx *cx, MirFunc *f, const UwHash *in_slots);
bool uw_wrap_with_closers(UwCx *cx, MirFunc *f);
bool uw_cover_shielded_slots(UwCx *cx, MirFunc *f);
bool uw_cover_inline_closes(UwCx *cx, MirFunc *f);

/* ---- mir_unwind_walk.c: the liveness walk ---- */

/* A run of instructions `first..=last` of one block covered by one registration of `values`. */
typedef struct UwStep {
    uint32_t at;
    OwnerSet target;
} UwStep;

typedef struct UwWindow {
    uint32_t first, last;
    OwnerSet values;
    UwStep *steps; /* the owners the window covers from an instruction on, where they differ */
    uint32_t nsteps, csteps;
} UwWindow;

typedef struct UwEvent {
    uint32_t at;
    OwnerSet owners;
} UwEvent;

typedef struct UwWalk {
    OwnerSet *entry;
    bool *has;
    UwWindow **plans;
    uint32_t *nplans, *cplans;
    MirValue **at_fault;
    uint32_t *nat_fault;
    UwEvent **events;
    uint32_t *nevents, *cevents;
    bool *plain;
} UwWalk;

/* What the walk reads about a function. */
typedef struct UwFacts {
    UwCx *cx;
    const MirFunc *f;
    const bool *owned_def; /* by value */
    uint32_t nowned;
    const UwHash *closed_by_with;
    const uint32_t *holes;
    UwHash *hoisted; /* by block */
} UwFacts;

bool uw_exits_at(const UwCx *cx, const MirInst *inst);
uint32_t uw_hole_step(uint32_t open, MirOp op, const MirInst *next);
uint32_t *uw_hole_states(UwCx *cx, const MirFunc *f);
UwWalk uw_analyze(const UwFacts *facts);
bool *uw_plain_blocks(UwCx *cx, const MirFunc *f, const uint32_t *holes);

/* ---- mir_unwind_flow.c: cleanup stacks and their rewrite ---- */

typedef struct UwNode {
    uint32_t parent, depth, owner;
    uint64_t tag;
    OwnerSet owners;
    PosMap depths;
} UwNode;

typedef struct UwStacks {
    MsArena *a;
    UwNode *nodes;
    uint32_t n, cap;
    uint32_t *table; /* open addressed: node + 1 */
    uint32_t tcap;
} UwStacks;

#define UW_ROOT 0u
#define UW_INF UINT32_MAX

typedef struct UwPlan {
    bool has_cut;
    uint32_t cut, keep;
    uint32_t *added, nadded;
} UwPlan;

typedef struct UwFlow {
    uint32_t *entry; /* the stack each block starts with */
    uint32_t *trim;  /* registrations a block leaves open; UW_INF for no limit */
} UwFlow;

void uws_init(UwStacks *s, MsArena *a);
uint32_t uws_depth(const UwStacks *s, uint32_t stack);
uint64_t uws_tag_at(const UwStacks *s, uint32_t stack, uint32_t depth);
UwPlan uws_plan(UwStacks *s, uint32_t stack, const OwnerSet *target);
uint32_t uws_extend(UwStacks *s, uint32_t stack, const uint32_t *owners, const uint64_t *tags,
                    uint32_t n, const OwnerSet *target);
bool uw_plan_flow(UwCx *cx, const MirFunc *f, const UwWalk *walk, UwStacks *stacks, UwFlow *out);
static inline bool uw_flow_carries(const UwFlow *fl, uint32_t bi) {
    return fl->entry[bi] != UW_ROOT || (fl->trim[bi] > 0 && fl->trim[bi] != UW_INF);
}

/* An instruction list under construction. */
typedef struct UwOut {
    MirInst *v;
    uint32_t n, cap;
} UwOut;
void uw_out_push(UwCx *cx, UwOut *o, MirInst inst);
MirInst uw_discard_inst(UwCx *cx, MirFunc *f, MirValue handle, MirLoc loc);
void uw_rewrite_flow_block(UwCx *cx, MirFunc *f, const UwWalk *walk, const UwFlow *flow,
                           UwStacks *stacks, UwHash *handles, uint32_t bi);
void uw_open_sync(UwCx *cx, MirFunc *f, UwStacks *stacks, uint32_t *at, UwOut *out,
                  const OwnerSet *target, MirLoc loc);
bool uw_open_close(UwCx *cx, MirFunc *f, UwStacks *stacks, uint32_t *at, MirLoc loc, MirInst *out);
/* One registration per value; the handles go to `handles` (`n` of them). */
void uw_push_each(UwCx *cx, MirFunc *f, UwOut *o, const MirValue *values, uint32_t n, MirLoc loc,
                  MirValue *handles);

/* ---- mir_unwind_own.c ---- */
void uw_own_resize(UwCx *cx, bool **def, uint32_t *n, uint32_t nvalues);
bool uw_owned_values(UwCx *cx, MirFunc *f, uint32_t fi, bool **def, uint32_t *n);

/* ---- mir_unwind_loops.c ---- */
bool uw_hoist_loops(UwCx *cx, MirFunc *f, bool **def, uint32_t *ndef, const UwHash *closed_by_with,
                    UwHash **hoisted);

#endif
