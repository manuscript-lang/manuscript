/* Ownership and borrow pass: the data every part of the pass shares. The Rust pass is
 * crates/ms-check/src/ownership; each part here is checked against it before it is called ported.
 * Nothing is global: a place lives in the arena it is built in. */
#ifndef MS_OWNERSHIP_H
#define MS_OWNERSHIP_H

#include "ms_rt/safe.h"

#include "ms/base.h"
#include "ms/facts.h"
#include "ms/tables.h"
#include "ms/types.h"

/* ---- places: a local binding and a path of projections ---- */

typedef enum MsStepKind {
    MS_STEP_FIELD,   /* a type field, named by `name` */
    MS_STEP_ELEMENT, /* some element of a collection: an index, a map value, an accessor */
    MS_STEP_INDEX    /* the element of a list at a non-negative literal index */
} MsStepKind;

typedef struct MsStep {
    MsStepKind kind;
    MsSym name;     /* MS_STEP_FIELD */
    uint64_t index; /* MS_STEP_INDEX */
} MsStep;

/* A part of a local binding's value. Immutable once built: `then` and `join` copy. */
typedef struct MsPlace {
    uint32_t root; /* the binding's identity */
    const MsStep *path;
    uint32_t len;
} MsPlace;

MsPlace ms_place_local(uint32_t root);
MsPlace ms_place_then(MsArena *a, MsPlace p, MsStep step);
MsPlace ms_place_join(MsArena *a, MsPlace p, const MsStep *more, uint32_t nmore);

/* Whether the two places share storage: same root, and one path is a prefix of the other.
 * Distinct fields and distinct literal list indexes are disjoint; any other pair of elements may
 * alias. */
bool ms_place_overlaps(MsPlace a, MsPlace b);

/* Source-like text: the root's name, then `.field`, `[..]` and `[3]`. */
void ms_place_show(MsBuf *out, const MsNames *names, MsPlace p, MsSym root_name);

/* ---- binding sets: the "every path has done X" sets of the backward walks ---- */

/* A dense set of binding identities below `nbits`, one bit each. The walks copy a set at every
 * branch and loop pass, so it is one array, not a hash set. */
typedef struct MsBits {
    uint64_t *words;
    uint32_t nbits;
} MsBits;

MsBits ms_bits_new(MsArena *a, uint32_t nbits);
MsBits ms_bits_copy(MsArena *a, MsBits s);
bool ms_bits_has(MsBits s, uint32_t i);
void ms_bits_add(MsBits s, uint32_t i);
void ms_bits_remove(MsBits s, uint32_t i);
void ms_bits_clear(MsBits s);
uint32_t ms_bits_count(MsBits s);
/* Keeps the members that `from` also has: the join of two paths that must both act. */
void ms_bits_meet(MsBits into, MsBits from);
/* Adds the members of `from`. */
void ms_bits_union(MsBits into, MsBits from);

/* ---- value classes: how a value of a type moves ---- */

/* Ordered, so the class of a container is the largest class of what it holds. */
typedef enum MsClass {
    MS_CLASS_COPY,     /* duplicated implicitly: scalars, types of those, plain-word natives */
    MS_CLASS_MOVE,     /* one owner; moves at its last use, `.clone()` copies */
    MS_CLASS_RESOURCE  /* a unique resource (`Closeable`): moves and cannot be copied */
} MsClass;

typedef struct MsClassifier MsClassifier;

/* A classifier over the checker's tables; `check` must outlive it. Results are kept per interned
 * type, so each type is classified once. Owned: free with ms_classifier_free. */
MsClassifier *ms_classifier_new(MsCheck *check) MS_NONNULL;
void ms_classifier_free(MsClassifier *classifier);

/* Declares that values of the type with this identity close themselves (a `Closeable`
 * implementation, or a `move close()` of the type's own). Later queries see it; call it before
 * classifying. */
void ms_classifier_mark_closeable(MsClassifier *classifier, MsSym type_id) MS_NONNULL;
/* Declares that the interface with this identity has a consuming `close`, so its values own what
 * they were made from. */
/* Marks the receiver of every method row that closes it (`Method::closes`). */
void ms_classifier_mark_methods(MsClassifier *classifier, const MsMethods *rows);
void ms_classifier_mark_owned_close(MsClassifier *classifier, MsSym interface_id) MS_NONNULL;

MsClass ms_classify(MsClassifier *classifier, MsTy type) MS_NONNULL;
/* Whether `type` declares a `close` of its own: its value is released by that close, never field by field. */
bool ms_closes_itself(MsClassifier *classifier, MsTy type) MS_NONNULL;
/* Whether `name` is the operation `Closeable` declares. */
bool ms_is_close_name(MsClassifier *classifier, MsSym name) MS_NONNULL;

/* ---- liveness: which use of a binding is its last ---- */

typedef enum MsUseState {
    MS_USE_NONE,  /* not a recorded use */
    MS_USE_LATER, /* the binding is used again on some path */
    MS_USE_LAST   /* no later use of the binding can run */
} MsUseState;

/* By expression node id. `next` is the earliest later use of the same binding, for diagnostics. */
typedef struct MsLiveness {
    uint8_t *state; /* MsUseState */
    uint32_t *next; /* node id, or MS_NONE */
    MsPos *pos;     /* where the use is written */
    /* By match-arm node id: the arm's payload bindings, which are consecutive binding ids. */
    uint32_t *arm_first;
    uint32_t *arm_count;
} MsLiveness;

MsLiveness ms_liveness_new(MsArena *arena, const MsFacts *facts);

/* Fills the liveness of one function body by a backward walk (`live.rs`). Returns false, leaving
 * the function unanalysed, for a statement or expression the walk does not handle yet. */
bool ms_liveness_function(MsLiveness *live, const MsFacts *facts, const MsFunc *function);

/* `ok(v)`, `Both(a, b)`: a call whose callee name the checker resolved to an enum case, so it built
 * a value rather than calling a function, a method or a function value. */
static inline bool ms_call_builds_case(const MsFacts *facts, const MsExpr *call) {
    const MsExpr *callee = call->u.call.callee;
    return callee->kind == MS_E_NAME && facts->res_kind[callee->id] == MS_RES_CASE;
}

/* ---- the pass ---- */

/* Runs the ownership rules over every function whose body the checker accepted, reporting what
 * the Rust pass reports. A function with a construct the pass does not handle yet is handed back
 * to the Rust checker: its `body_checked` flag is cleared. Call after ms_module_check_bodies. */
void ms_module_check_ownership(MsCheck *c, MsModId module);

#endif
