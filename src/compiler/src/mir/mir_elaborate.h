/* elaborate: the state its source files share (mir_elaborate*.c). Port of elaborate.rs.
 *
 * Drop elaboration places the scope-exit cleanup of a Raw function, one whose owned values are
 * left to scope markers (`scope.begin`, `scope.own`, `scope.end`, `scope.disown`, `scope.mark`).
 * A dataflow over the function gives each owner a move state; the emitter then drops or closes
 * what a scope still holds where the scope ends, with drop flags for owners moved on some paths. */
#ifndef MS_MIR_ELABORATE_H
#define MS_MIR_ELABORATE_H

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mir/mir_unwind.h" /* UwHash, the open-addressed maps and sets */
#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"
#include "ms/mir_persist.h"

/* The move state of an owner: a small id so a state compares as an integer. The first ids are the
 * plain kinds; a partial move (alternative, case, mask of taken fields) is interned past them. */
enum {
    EL_LIVE,
    EL_MOVED,        /* consumed; kept only for slot owners and flagged owners */
    EL_MAYBE,        /* moved on some paths into a join: the owner carries a drop flag */
    EL_CLOSED,       /* a slot owner the program closed by hand (`scope.mark 1`) */
    EL_MAYBE_CLOSED, /* closed by hand on some paths: a flag says which */
    EL_CLOSED_OR_MOVED,
    EL_PLAIN_KINDS
};
typedef uint32_t ElSt;

typedef struct ElPart { uint32_t alt, cs, mask; } ElPart;

/* The owners in scope in definition order, persistent so a copy shares everything with the
 * original (a function of N blocks and N owners must not copy N owners per block). */
typedef struct ElState {
    PosMap seq;   /* definition position -> value << 32 | ElSt */
    PosMap at;    /* value -> definition position */
    OwnerSet odd; /* the owners in a state a join produces */
    uint32_t next;
} ElState;

/* One owner of a state, in definition order. */
typedef struct ElOwner { uint32_t pos; MirValue v; ElSt st; } ElOwner;

typedef struct ElList { MirValue *v; uint32_t n, cap; } ElList;

/* What a function's scope markers say, and the pass-wide runtime hooks. */
typedef struct ElCx {
    const MirModule *m;
    MsArena *ma;            /* scratch for this function: states, tables */
    const MirFunc *f;       /* the function being walked (its stand-in is in the module) */
    uint32_t nvalues0;      /* values the function had before the pass */
    int64_t *tag_scope;     /* per value: the scope that owns it, -1 when untagged */
    int64_t *tag_kind;      /* the owner's kind (0 drop, 1 close, k >= 2 slot closed by k - 2) */
    ElList *owners;         /* per scope: the values it owns, in tag order */
    int64_t *parent;        /* per scope; -1 for the root */
    bool *has_parent;
    uint32_t nscopes;
    uint32_t close;         /* the module's `close` function or MIR_NONE */
    uint32_t discard, cancel, shield_enter, shield_exit; /* extern ids or MIR_NONE */
    UwHash disown_moves;    /* flagged owners a `scope.disown` ahead of the consuming op moves */
    UwHash cancel_blocks;   /* the blocks of the function's cancel exits */
    struct ElCancel *all;   /* what cancel exits read about the module, or NULL when none are built */
    uint32_t fi;            /* the function being walked */
    ElPart *parts;          /* interned partial-move states, id EL_PLAIN_KINDS + index */
    uint32_t nparts, cparts;
    char err[192];
} ElCx;

/* Reports an error: formats it into the context and returns false. */
bool el_fail(ElCx *cx, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

ElSt el_part(ElCx *cx, uint32_t alt, uint32_t cs, uint32_t mask);
bool el_is_part(ElSt s);
const ElPart *el_part_of(const ElCx *cx, ElSt s);
bool el_is_odd(ElSt s);

/* State operations. `get` returns false when `v` is not an owner. */
void el_push(ElCx *cx, ElState *st, MirValue v, ElSt s);
bool el_get(const ElState *st, MirValue v, ElSt *s);
void el_set(ElCx *cx, ElState *st, MirValue v, ElSt s);
void el_remove(ElCx *cx, ElState *st, MirValue v);
bool el_position_of(const ElState *st, MirValue v, uint32_t *pos);
/* The owners in definition order: `*n` of them, in the context's arena. */
ElOwner *el_owners(ElCx *cx, const ElState *st, uint32_t *n);
/* The owners a join left uncertain, in definition order. */
ElOwner *el_odd(ElCx *cx, const ElState *st, uint32_t *n);
int el_by_position_cmp(const void *x, const void *y); /* qsort order of ElOwner */
bool el_state_equal(const ElState *a, const ElState *b);

/* Whether `v` owns a memory slot (`scope.own S K p`, K >= 2): the owner is the slot's address. */
bool el_is_slot_owner(const ElCx *cx, MirValue v);
bool el_tagged(const ElCx *cx, MirValue v);

/* The move state after `inst`, and across an edge or a join. */
bool el_apply(ElCx *cx, ElState *st, const MirInst *inst);
bool el_edge_state(ElCx *cx, const ElState *st, const MirTarget *t, ElState *out);
bool el_merge(ElCx *cx, const ElState *old, const ElState *next, ElState *out);
bool el_consume_value(ElCx *cx, ElState *st, MirValue v);
bool el_own_params(const ElCx *cx, uint32_t b, MirValue **out, uint32_t *n);

/* The move state on entry to every reachable block, to a fixpoint. `entry` has one slot per
 * block; `has` says whether the block was reached. */
bool el_analyze(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has);

/* Emits the function's cleanup. `flagged` owners carry drop flags. */
typedef struct ElEm {
    ElCx *cx;
    MirModule *m;
    MirFunc *f;
    UwHash flagged;  /* owners that carry a drop flag */
    UwHash ckeys;    /* owner -> the key of its closed-by-hand flag */
    UwHash hkeys;    /* owner -> the key of its live cleanup entry, when it can be refilled */
    UwHash flags;    /* the current flag value of each flagged owner (reset per block) */
    UwHash handles;  /* owner -> the `cleanup.push` handle of each closing owner */
    MirValue pending; /* the value the block returns, still to be returned after its scope ends */
    bool counts_depth;
    bool in_cancel;
} ElEm;

/* The flag parameters of one block: (key, parameter) pairs. */
typedef struct ElFparams { MirValue *key, *param; uint32_t n, cap; } ElFparams;

bool el_emit_block(ElEm *em, uint32_t b, const ElState *entry, const ElFparams *fparams);

/* ---- emission helpers (mir_elaborate_emit.c) ---- */

#define EM_NO_RESULT MIR_NONE

/* Appends an instruction to block `at`, with a fresh result of type `ty` unless `EM_NO_RESULT`. */
MirValue em_push(ElEm *em, uint32_t at, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                 MirTy ty);
MirValue em_bconst(ElEm *em, uint32_t at, bool value);
MirValue em_iconst(ElEm *em, uint32_t at, int64_t value);
void em_br(ElEm *em, uint32_t at, MirBlock to, const MirValue *args, uint32_t nargs);
void em_condbr(ElEm *em, uint32_t at, MirValue cond, MirBlock then, MirBlock els);
MirValue em_block_param(ElEm *em, MirBlock block, MirTy ty, MirMode mode);
MirBlock em_new_block(ElEm *em); /* an empty block with no source position */
MirImm em_imm_func(uint32_t id);
MirImm em_imm_case(uint32_t alt, uint32_t cs);
void em_discard(ElEm *em, uint32_t at, MirValue v);
bool em_closer(ElEm *em, MirValue v, uint32_t *close);
bool em_register(ElEm *em, uint32_t at, MirValue v);
void em_drop_owned(ElEm *em, uint32_t at, MirValue v);
MirValue em_is_error(ElEm *em, uint32_t at, MirValue r);
/* Runs the fallible close `rc` of slot owner `v`, shielded; `*r` is its `Result`. */
bool em_close_result(ElEm *em, uint32_t at, MirValue v, uint32_t rc, MirValue *r);
bool em_flag_of(const UwHash *h, MirValue key, MirValue *out);

/* Closes or drops what a scope still holds at its end (mir_elaborate_close.c); returns the block
 * to continue in. */
bool em_exit(ElEm *em, uint32_t *cur, ElState *st, int64_t scope);
bool em_cleanup_one(ElEm *em, uint32_t *at, MirValue v, ElSt s, MirValue *outcome);

/* The pass over one function; `f` is out of the module and the module holds its stand-in. */
bool el_function(ElCx *cx, MirModule *m, MirFunc *f);
void el_tags(ElCx *cx);

/* ---- cancel exits (mir_elaborate_cancel.c, _sites.c, _convert.c) ----
 *
 * Port of cancel_exit.rs. After every call that can park, a Raw function of a task program tests
 * the task's `unwinding` byte and leaves through a block built like an early `return`:
 *
 *     r = call f(..); u = call.rt msrt_unwinding(); c = ne u, 0; condbr c, leave, next
 *     leave: call.rt msrt_unwinding_pause(); forget r; drop <untagged live owners>;
 *            scope.end S_n; ..; scope.end S_1; br tail
 *     tail:  call.rt msrt_unwinding_resume(); call.rt msrt_cleanup_truncate(base); %z = undef; ret %z
 *
 * Elaboration then turns the `scope.end` markers into the drops and closes the move state calls
 * for. A function converts only when every owned value live at a park is a scope owner or plainly
 * droppable; the others keep the hybrid exit. */

/* A closure type and a function a `closure.new` of that type makes callable, in first-seen order. */
typedef struct ElTarget { MirTy ty; uint32_t seq, func; } ElTarget;

typedef struct ElCancel {
    MsArena arena;
    uint32_t nfuncs;
    bool *parks;
    UwTable safe;    /* per function and parameter: a slot pointer it only borrows */
    /* Per function: converted (or free of parks), so its cancel exits leave every `var` slot
     * parameter as the normal exit would. Starts true for every function with such a parameter and
     * is lowered until it holds, so a cycle of callers and callees is proved together. */
    bool *restores;
    uint32_t unwinding, base, truncate, pause, resume; /* the runtime entries the exits call */
    ElTarget *closures;
    uint32_t nclosures;
} ElCancel;

/* The context for a module that starts tasks, or NULL when it does not. */
ElCancel *el_cancel_new(MirModule *m);
void el_cancel_free(ElCancel *all);

/* The functions in the order their conversion runs: a callee before its callers (a cycle is cut
 * where it is first met), so `restores` is known when a caller asks. Natural order without `all`. */
uint32_t *el_callee_first(MsArena *a, const MirModule *m, const ElCancel *all);

/* Whether call `inst` leaves the slot at argument `k` as its normal return would: a function whose
 * exits restore its `var` slots, or a closure call whose possible targets all do. */
bool el_restoring_callee(const ElCancel *all, const MirModule *m, const MirFunc *f,
                         const MirInst *inst, uint32_t k);

/* Lowers `restores` until each function that keeps it can build its exits under the others'. */
void el_settle_restores(ElCancel *all, MirModule *m, const uint32_t *order, const ElCx *shared);

/* Sorted sets of ids and plain vectors of them, in an arena. */
typedef struct ElIds { uint32_t *v; uint32_t n, cap; } ElIds;
bool el_ids_has(const ElIds *s, uint32_t x);
void el_ids_add(MsArena *a, ElIds *s, uint32_t x);
void el_ids_del(ElIds *s, uint32_t x);
ElIds el_ids_clone(MsArena *a, const ElIds *s);
void el_ids_push(MsArena *a, ElIds *s, uint32_t x);
bool el_ids_contains(const ElIds *s, uint32_t x);
void el_ids_remove_all(ElIds *s, uint32_t x);

typedef struct ElPair { MirValue a, b; MirTy ty; } ElPair;
typedef struct ElRefill {
    MirValue slot, whole, part_slot;
    MirTy part_ty, whole_ty;
    MirInst fill; /* the `type.fill` the normal path runs, copied for the exit */
} ElRefill;

/* A parking call, with what is live and which scopes are open right after it. */
typedef struct ElSite {
    uint32_t block, inst;
    MirValue *explicit_drops; uint32_t nexplicit; /* live owned values no open scope releases */
    uint32_t *scopes; uint32_t nscopes;
    ElPair *putback; uint32_t nputback;     /* (slot, value): a taken value goes back */
    ElRefill *refills; uint32_t nrefills;   /* a part moved out is taken back, filled in, put back */
    ElPair *returns; uint32_t nreturns;     /* (var slot, local slot, type) */
    ElPair *slot_drops; uint32_t nslot_drops; /* (local slot, type): taken out and dropped */
} ElSite;

typedef struct ElSites { ElSite *v; uint32_t n, cap; } ElSites;

/* The parking calls of `f` in block order; false when a value live at one has no rule. */
bool el_cancel_sites(const ElCancel *all, const MirModule *m, const MirFunc *f, ElCx *cx,
                     ElSites *out);

/* Adds the cancel exits to `f`; `cx->cancel_blocks` gets the leave blocks. Does nothing when the
 * function stays hybrid. */
void el_cancel_convert(ElCancel *all, MirModule *m, MirFunc *f, ElCx *cx);

#endif
