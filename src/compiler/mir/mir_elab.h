/* compiler/mir/mir_elab.h: drop elaboration, the state its source files share (mir_elab*.c).
 *
 * Elaboration places the scope-exit cleanup of a Raw function, one whose owned values are left to scope
 * markers (`scope.begin`, `scope.own`, `scope.end`, `scope.disown`, `scope.mark`). A dataflow over the
 * function gives each owner a move state; the emitter then drops or closes what a scope still holds where
 * the scope ends, with drop flags for owners moved on some paths. */
#ifndef MS_COMPILER_MIR_MIR_ELAB_H
#define MS_COMPILER_MIR_MIR_ELAB_H

#include "base/strbuild.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_hash.h"
#include "compiler/mir/mir_pass.h"
#include "compiler/mir/mir_persist.h"

/* Runs the pass over every Raw function. On failure the error text names the function. */
bool mir_elaborate(MirModule *module, MsStrBuild *error);

/* The move state of an owner: a small id so a state compares as an integer. The first ids are the plain
 * kinds; a partial move (alternative, case, mask of taken fields) is interned past them. */
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

typedef struct ElPart {
  uint32_t alt, cs, mask;
} ElPart;

/* The owners in scope in definition order, persistent so a copy shares everything with the original (a
 * function of N blocks and N owners must not copy N owners per block). */
typedef struct ElState {
  PosMap seq;   /* definition position -> value << 32 | ElSt */
  PosMap at;    /* value -> definition position */
  OwnerSet odd; /* the owners in a state a join produces */
  uint32_t next;
} ElState;

/* One owner of a state, in definition order. */
typedef struct ElOwner {
  uint32_t pos;
  MirValue v;
  ElSt st;
} ElOwner;

/* What a function's scope markers say, and the pass-wide runtime hooks. All tables live in `ma`, a scratch
 * arena for this function. */
typedef struct ElCx {
  const MirModule *m;
  MsArena *ma;
  MsStrBuild *error;     /* the failure text, written by el_fail */
  const MirFunc *f;      /* the function being walked (its stand-in is in the module) */
  uint32_t nvalues0;     /* values the function had before the pass */
  int64_t *tag_scope;    /* per value: the scope that owns it, -1 when untagged */
  MirBits cancel_end;    /* owners whose entry is cancelled, not discarded, where their scope ends: an outer scope pushed after them */
  int64_t *tag_kind;     /* the owner's kind (0 drop, 1 close, k >= 2 slot closed by k - 2) */
  MirIdList *owners;     /* per scope: the values it owns, in tag order */
  int64_t *parent;       /* per scope; -1 for the root */
  bool *has_parent;
  uint32_t nscopes;
  uint32_t close;        /* the module's `close` function or MIR_NONE */
  uint32_t discard, cancel, shield_enter, shield_exit; /* extern ids or MIR_NONE */
  MirHash param_owned;   /* values that are owning block parameters */
  MirHash disown_moves;  /* flagged owners: they stay tracked as moved once an op consumes them */
  MirHash unpin_live;    /* owning results a `scope.unpin` hands back to their variable: still live after it */
  MirHash reowned;       /* owners a scope registers at more than one place (a variable at each exit): consumed, they stay moved */
  ElPart *parts;         /* interned partial-move states, id EL_PLAIN_KINDS + index */
  uint32_t nparts, cparts;
} ElCx;

/* Records the failure and returns false. */
#define el_fail(cx, ...) (ms_strbuild_printf((cx)->error, __VA_ARGS__), false)

ElSt el_part(ElCx *cx, uint32_t alt, uint32_t cs, uint32_t mask);
bool el_is_part(ElSt state);
const ElPart *el_part_of(const ElCx *cx, ElSt state);
bool el_is_odd(ElSt state);

/* State operations. `get` returns false when `value` is not an owner. */
void el_push(ElCx *cx, ElState *state, MirValue value, ElSt kind);
bool el_get(const ElState *state, MirValue value, ElSt *kind);
void el_set(ElCx *cx, ElState *state, MirValue value, ElSt kind);
void el_remove(ElCx *cx, ElState *state, MirValue value);
bool el_position_of(const ElState *state, MirValue value, uint32_t *position);
/* The owners in definition order: `*count` of them, in the context's arena. */
ElOwner *el_owners(ElCx *cx, const ElState *state, uint32_t *count);
/* Orders two ElOwner by definition position, for ms_sort. */
int64_t el_owner_by_position(uint8_t *env, const uint8_t *x, const uint8_t *y);
/* The owners a join left uncertain, in definition order. */
ElOwner *el_odd(ElCx *cx, const ElState *state, uint32_t *count);
bool el_state_equal(const ElState *x, const ElState *y);

/* Whether `value` owns a memory slot (`scope.own S K p`, K >= 2): the owner is the slot's address. */
bool el_is_slot_owner(const ElCx *cx, MirValue value);
bool el_tagged(const ElCx *cx, MirValue value);

/* The move state after `inst`, and across an edge or a join. */
bool el_apply(ElCx *cx, ElState *state, const MirInst *inst);
bool el_edge_state(ElCx *cx, const ElState *state, const MirTarget *target, ElState *out);
bool el_merge(ElCx *cx, const ElState *old, const ElState *next, ElState *out);
bool el_consume_value(ElCx *cx, ElState *state, MirValue value);
/* The block parameters that own a value, in the context's arena. */
MirValue *el_own_params(const ElCx *cx, uint32_t block, uint32_t *count);

/* The move state on entry to every reachable block, to a fixpoint. `entry` has one slot per block; `has`
 * says whether the block was reached. */
bool el_analyze(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has);

/* The scope tags of a function (mir_elab_tags.c). */
void el_tags(ElCx *cx);
void el_prune_undominated_drops(ElCx *cx);
void el_tags_free(ElCx *cx); /* frees the owner lists */

/* Emits the function's cleanup. `flagged` owners carry drop flags. */
typedef struct ElEm {
  ElCx *cx;
  MirModule *m;
  MirFunc *f;
  MirHash flagged; /* owners that carry a drop flag */
  MirHash ckeys;   /* owner -> the key of its closed-by-hand flag */
  MirHash hkeys;   /* owner -> the key of its live cleanup entry, when it can be refilled */
  MirHash flags;   /* the current flag value of each flagged owner (reset per block) */
  MirHash handles; /* owner -> the `cleanup.push` handle of each closing owner */
  MirValue pending; /* the value the block returns, still to be returned after its scope ends */
  /* The last cancel emitted: a refill right after it, with nothing between that can exit, reuses the entry. */
  struct {
    MirValue value, handle;
    uint32_t block;
    size_t index;
  } cancelled;
  bool counts_depth;
} ElEm;

/* The flag parameters of one block: (key, parameter) pairs. */
typedef struct ElFparams {
  MirIdList key, param;
} ElFparams;

bool el_emit_block(ElEm *em, uint32_t block, const ElState *entry, const ElFparams *fparams);

/* ---- emission helpers (mir_elab_emit.c) ---- */

#define EM_NO_RESULT MIR_NONE

/* Appends an instruction to block `at`, with a fresh result of type `ty` unless `EM_NO_RESULT`. */
MirValue em_push(ElEm *em, uint32_t at, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty);
MirValue em_bconst(ElEm *em, uint32_t at, bool value);
MirValue em_iconst(ElEm *em, uint32_t at, int64_t value);
void em_br(ElEm *em, uint32_t at, MirBlock to, const MirValue *args, uint32_t nargs);
void em_condbr(ElEm *em, uint32_t at, MirValue cond, MirBlock then, MirBlock otherwise);
MirValue em_block_param(ElEm *em, MirBlock block, MirTy ty, MirMode mode);
MirBlock em_new_block(ElEm *em); /* an empty block with no source position */
MirImm em_imm_func(uint32_t id);
MirImm em_imm_case(uint32_t alt, uint32_t cs);
void em_discard(ElEm *em, uint32_t at, MirValue value);
bool em_closer(ElEm *em, MirValue value, uint32_t *close);
bool em_register(ElEm *em, uint32_t at, MirValue value);
void em_drop_owned(ElEm *em, uint32_t at, MirValue value);
MirValue em_is_error(ElEm *em, uint32_t at, MirValue result);
/* Runs the fallible close `close` of slot owner `value`, shielded; `*result` is its `Result`. */
bool em_close_result(ElEm *em, uint32_t at, MirValue value, uint32_t close, MirValue *result);
bool em_flag_of(const MirHash *map, MirValue key, MirValue *out);

/* Closes or drops what a scope still holds at its end (mir_elab_close.c). */
bool em_exit(ElEm *em, uint32_t *cur, ElState *state, int64_t scope);
bool em_cleanup_one(ElEm *em, uint32_t *at, MirValue value, ElSt state, MirValue *outcome);

/* Edge, flag and slot-refill code (mir_elab_edge.c, mir_elab_flags.c). */
bool em_edges(ElEm *em, uint32_t cur, MirTerm *term, const ElFparams *fparams);
bool em_refill(ElEm *em, uint32_t *at, MirValue value, bool has_state, ElSt was);
bool em_reregister(ElEm *em, uint32_t at, MirValue value, MirValue key, MirValue *handle);
void em_cancel(ElEm *em, uint32_t at, MirValue value);
void em_set_held(ElEm *em, uint32_t at, MirValue value);
void em_birth(ElEm *em, uint32_t at, MirValue value);
MirValue em_move_arg(ElEm *em, uint32_t at, MirValue arg);

#endif
