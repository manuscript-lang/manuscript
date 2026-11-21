/* range: the state and helpers its source files share (opt_range*.c). Port of
 * the former Rust crates/ms-mir/src/opt/range.rs and range/prove.rs; see opt_range.c for the algorithm. */
#ifndef MS_OPT_RANGE_H
#define MS_OPT_RANGE_H

#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"

__extension__ typedef __int128 RgWide;

/* ---- arena helpers ---- */

/* Zeroed storage for `n` elements of `elem` bytes. */
static inline void *rg_zalloc(MsArena *a, size_t n, size_t elem) {
    size_t bytes = 0;
    if (!ms_size_mul(n, elem, &bytes)) {
        ms_oom();
    }
    void *p = ms_alloc(a, bytes != 0 ? bytes : 1, 16);
    memset(p, 0, bytes);
    return p;
}
#define RG_ZNEW(a, T, n) ((T *)rg_zalloc((a), (n), sizeof(T)))

/* `arr` (with `n` elements and room for `*cap`) grown to at least one more element. */
void *rg_grow(MsArena *a, void *arr, uint32_t n, uint32_t *cap, size_t elem);
#define RG_PUSH(a, arr, n, cap, T, x) \
    do { \
        if ((n) == (cap)) { \
            (arr) = (T *)rg_grow((a), (arr), (n), &(cap), sizeof(T)); \
        } \
        (arr)[(n)++] = (x); \
    } while (0)

/* ---- intervals ---- */

typedef struct RgItv {
    int64_t lo, hi;
} RgItv;

#define RG_TOP ((RgItv){INT64_MIN, INT64_MAX})
#define RG_BOOL ((RgItv){0, 1})

static inline RgItv rg_point(int64_t v) { return (RgItv){v, v}; }
static inline bool rg_is_point(RgItv x) { return x.lo == x.hi; }
static inline RgItv rg_join(RgItv x, RgItv y) {
    return (RgItv){x.lo < y.lo ? x.lo : y.lo, x.hi > y.hi ? x.hi : y.hi};
}
static inline bool rg_itv_eq(RgItv x, RgItv y) { return x.lo == y.lo && x.hi == y.hi; }

/* The intersection; false when it is empty. */
static inline bool rg_meet(RgItv x, RgItv y, RgItv *out) {
    const int64_t lo = x.lo > y.lo ? x.lo : y.lo;
    const int64_t hi = x.hi < y.hi ? x.hi : y.hi;
    if (lo > hi) {
        return false;
    }
    *out = (RgItv){lo, hi};
    return true;
}

static inline bool rg_fits(RgWide lo, RgWide hi) { return lo >= INT64_MIN && hi <= INT64_MAX; }

/* An exact range clamped to `i64` (checked operations fault outside it). */
static inline RgItv rg_clamp(RgWide lo, RgWide hi) {
    if (lo < INT64_MIN) {
        lo = INT64_MIN;
    }
    if (hi > INT64_MAX) {
        hi = INT64_MAX;
    }
    return lo > hi ? RG_TOP : (RgItv){(int64_t)lo, (int64_t)hi};
}

/* An exact range, or top when it leaves `i64` (wrapping operations). */
static inline RgItv rg_exact_itv(RgWide lo, RgWide hi) {
    return rg_fits(lo, hi) ? (RgItv){(int64_t)lo, (int64_t)hi} : RG_TOP;
}

typedef enum RgArith { RG_MUL, RG_DIV } RgArith;
/* The least and greatest of `x op y` over the four corners. */
void rg_corners(RgArith op, RgItv x, RgItv y, RgWide *lo, RgWide *hi);

bool rg_cmp_holds(MirCc cc, int64_t a, int64_t b);
MirCc rg_cc_negated(MirCc cc);

/* ---- environments ---- */

/* What is known at a program point: intervals of values (sorted by value) and relations
 * `a < b` (strict) or `a <= b` between values. Storage comes from `arena`. */
typedef struct RgEnt {
    MirValue v;
    RgItv itv;
} RgEnt;

typedef struct RgRel {
    MirValue a, b;
    bool strict;
} RgRel;

typedef struct RgEnv {
    MsArena *arena;
    RgEnt *ent;
    uint32_t nent, cent;
    RgRel *rel;
    uint32_t nrel, crel;
} RgEnv;

bool rg_env_lookup(const RgEnv *e, MirValue v, RgItv *out);
void rg_env_narrow(RgEnv *e, MirValue v, RgWide lo, RgWide hi);
void rg_env_add_rel(RgEnv *e, MirValue a, MirValue b, bool strict);
RgEnv rg_env_clone(MsArena *arena, const RgEnv *src);

/* ---- the analysis ---- */

typedef enum RgEdgeKind { RG_PLAIN, RG_THEN, RG_ELSE, RG_CASE, RG_DEFAULT } RgEdgeKind;

/* One edge into a block: the branching block, how the edge is taken and the block arguments. */
typedef struct RgEdge {
    uint32_t pred;
    uint8_t kind;
    int64_t key; /* RG_CASE: the case value */
    const MirValue *args;
    uint32_t nargs;
} RgEdge;

typedef struct RgSquare {
    uint32_t block, index, next;
} RgSquare;

typedef struct RgFa {
    const MirModule *m;
    const MirFunc *f;
    uint32_t nv, nb, nrpo;
    MirBlock *rpo, *idom;
    uint32_t *rpo_pos;
    /* The instruction that defines each value (MIR_NONE for a parameter) and, for a parameter of
     * a block other than the entry, the block and position. */
    uint32_t *def_blk, *def_idx, *param_blk, *param_idx;
    /* The checked squares `y * y` by `y`: each fits in an `i64` on every path through it, which
     * bounds `x * y + j` for `x, j < y`. */
    uint32_t *sq_head;
    RgSquare *squares;
    uint32_t nsq, csq;
    uint32_t *in_start; /* block b's incoming edges are in[in_start[b]..in_start[b + 1]] */
    RgEdge *in;
    RgItv *base;
    uint8_t *has_base;
    RgEnv *envs;
    uint32_t *widen;
    MirValue *lenof;   /* length origin of a `list.len` result, MIR_NONE for other values */
    MirValue *lengths; /* length origin of each value */
    uint8_t *byte_lists;
    uint32_t *last_read; /* by class: the last block position that reads it */
    MsArena arena;       /* the function's analysis */
    MsArena gen[2];      /* the environments of this round and the last */
    MsArena tmp;         /* scratch that dies with the query that made it */
    uint32_t round;
} RgFa;

/* The scratch arena. Nothing frees it while a query runs: its owner calls `rg_tmp_reset` between
 * queries, when no environment made in it is still in use. */
static inline MsArena *rg_tmp(RgFa *fa) { return &fa->tmp; }
static inline void rg_tmp_reset(RgFa *fa) { ms_arena_free(&fa->tmp); }

const MirInst *rg_def_inst(const RgFa *fa, MirValue v);
bool rg_constant(const RgFa *fa, MirValue v, int64_t *out);
uint32_t rg_class(const RgFa *fa, MirValue v);
bool rg_get(const RgFa *fa, MirValue v, const RgEnv *env, RgItv *out);
bool rg_tracked(MirTy ty);
RgEnv rg_edge_env(RgFa *fa, MsArena *arena, const RgEdge *e);
void rg_build_env(RgFa *fa, uint32_t bi, RgEnv *out);
void rg_refine_cond(RgFa *fa, MirValue cond, bool truth, RgEnv *env);
bool rg_eval(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out);

/* ---- length origins (opt_range_len.c) ---- */

MirValue *rg_length_origins(MsArena *arena, const MirModule *m, const MirFunc *f);
uint8_t *rg_byte_lists(MsArena *arena, const MirModule *m, const MirFunc *f);
void rg_alias_loop_lists(MsArena *scratch, const MirModule *m, const MirFunc *f, MirValue *lengths);
void rg_counted_lists(const RgFa *fa, MirValue *lenof);

/* ---- proofs (opt_range_prove.c) ---- */

typedef enum RgEditKind { RG_EDIT_OP, RG_EDIT_BOOL, RG_EDIT_INT, RG_EDIT_TERM } RgEditKind;

typedef struct RgEdit {
    uint8_t kind;
    uint8_t op; /* RG_EDIT_OP: the new MirOp; RG_EDIT_BOOL: the value */
    uint32_t block, index;
    int64_t value; /* RG_EDIT_INT */
    MirTerm term;  /* RG_EDIT_TERM */
} RgEdit;

typedef struct RgEdits {
    RgEdit *v;
    uint32_t n, cap;
} RgEdits;

void rg_collect_edits(RgFa *fa, RgEdits *out);
bool rg_decide(const RgFa *fa, MirCc cc, MirValue a, MirValue b, RgItv x, RgItv y,
               const RgEnv *env, bool *result);
bool rg_same_value(const RgFa *fa, MirValue a, MirValue b);
bool rg_list_length(const RgFa *fa, MirValue v, int64_t *out);

#endif
