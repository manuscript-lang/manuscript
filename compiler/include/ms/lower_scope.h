/* Ownership scopes for the lowering (crates/ms-lower func.rs `push_scope`, `own_raw_value_in`,
 * `end_raw`; proposals/elaborate-drops.md). Lowering emits only markers: `scope.begin` (once, with
 * the enclosing scope), `scope.own` for each owned value, `scope.disown` when a value moves on
 * without an op that consumes it, and `scope.end` where control leaves. The `elaborate` pass places
 * every drop from them, so lowering never emits a drop and keeps no per-path state.
 *
 * Use, with `b` the function's builder:
 *   LScopes s; lscope_init(&s, &b);
 *   lscope_push(&s);                      // a block, a loop body, an arm
 *   lscope_own(&s, v, 0);                 // `v` is owned by the innermost scope
 *   lscope_exit_to(&s, depth);            // before `return` (depth 0), `break` or `continue`
 *   lscope_pop(&s, !dead);                // the fall-through end; false when control cannot reach it
 * A scope that owns nothing emits nothing. Beginning is lazy: the first `lscope_own` begins every
 * enclosing scope not yet begun, outermost first, because an error exit of the pass walks the chain. */
#ifndef MS_LOWER_SCOPE_H
#define MS_LOWER_SCOPE_H

#include "ms/mir_builder.h"

typedef struct LScope {
    uint32_t id;
    uint32_t parent; /* the enclosing scope's id plus one, 0 for the outermost */
    bool begun;
} LScope;

typedef struct LScopes {
    MirBuilder *b;
    LScope *stack;
    uint32_t depth, cap;
    uint32_t next_id;
} LScopes;

/* No scope is open: the function's outermost scope is the first `lscope_push`. */
void lscope_init(LScopes *s, MirBuilder *b);
/* Opens a scope; returns its depth (the count of open scopes before it). */
uint32_t lscope_push(LScopes *s);
/* `scope.own S K v` in the innermost scope; `kind` is 0 for a plain drop. */
void lscope_own(LScopes *s, MirValue v, uint32_t kind);
/* The same in the open scope at `depth` (a `var` local is owned by the scope that declared it, at
 * each exit, with the value it holds there). */
void lscope_own_in(LScopes *s, uint32_t depth, MirValue v, uint32_t kind);
/* `v` moved on without an op that consumes it: it is no longer a scope's to drop on this path. */
void lscope_disown(LScopes *s, MirValue v);
/* `scope.end` for every open scope at or above `depth`, innermost first, without closing them. */
void lscope_exit_to(LScopes *s, uint32_t depth);
/* Closes the innermost scope; `reached` says control arrives at its end, which emits its end. */
void lscope_pop(LScopes *s, bool reached);

#endif
