/* The state shared by the files of the body lowering (lower_body.c and the files it hands
 * constructs to). The lowering is one translation unit (libms.c): helpers stay `static` in their
 * file and are visible to the files included after it; a construct a later file lowers is
 * declared here and called from lower_body.c. Prefix: `lb_`. */
#ifndef MS_LOWER_INTERNAL_H
#define MS_LOWER_INTERNAL_H

#include "ms/check.h"
#include "ms/facts.h"
#include "ms/lower_scope.h"
#include "ms/mir_builder.h"

/* The loop being lowered: where `continue` and `break` go. Lives on the lowering's stack. A
 * `for` has a step block that only exists once something branches to it. */
typedef struct LbLoop {
    MirBlock next, exit; /* `continue` goes to `next`, `break` to `exit` */
    struct LbLoop *outer;
    bool broke;   /* a `break` branches to `exit` */
    bool stepped; /* a branch to `next` exists (a `while` has it from the start) */
    uint32_t scope; /* the depth of the body's ownership scope: `break` and `continue` leave down to it */
} LbLoop;

/* An owned `var` String: the value it holds is owned by its scope at every exit, since the
 * variable is reassigned and its current value differs from one exit to the next. */
typedef struct LbVarOwner {
    uint32_t binding;
    uint32_t depth; /* the scope that declared it */
} LbVarOwner;

/* A lowered expression: the value, and whether the holder must drop it. */
typedef struct LbVal {
    MirValue v;
    bool owned;
} LbVal;

/* A lambda whose closure function is added but not yet lowered: `func` is its stub and `caps`
 * the outer bindings its environment holds, in order. */
typedef struct LbJob {
    const MsExpr *lambda;
    uint32_t func;
    uint32_t *caps;
    uint32_t ncaps;
} LbJob;

typedef struct Lb {
    const MsCheck *c;
    const MsFacts *facts;
    MirModule *m;
    MirBuilder b;
    LScopes scopes; /* ownership scopes: the function body is depth 0 */
    MsTy int_ty, float_ty, bool_ty, string_ty, void_ty;
    /* By binding id: the value a `let` or parameter names, or the variable a `var` is. */
    MirValue *value_of;
    MirVar *var_of;
    uint32_t *func_of;    /* by symbol id: the module function a call reaches, or MIR_NONE */
    uint32_t *thunk_of;   /* by symbol id: the closure function forwarding to it, or MIR_NONE */
    LbJob *jobs;          /* the lambdas made by the function being lowered, to lower after it */
    uint32_t njobs, cjobs;
    bool closure;         /* lowering a closure body: no call depth, no `var` parameters */
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE */
    const MsDecl *decl;   /* the function being lowered */
    const MsStmt *stmt;   /* the statement being lowered: every instruction in it reports its position */
    LbLoop *loop;         /* the innermost loop around the statement, or NULL */
    struct LbVarOwner *vars; /* the owned `var` Strings in scope, innermost last */
    uint32_t nvars, cvars;
    bool dead;            /* control cannot reach the current position */
    bool ok;              /* false once a construct outside the handled set is met */
} Lb;

/* lower_closure.c: function values and lambdas. */
MirTy lb_fn_ty(const Lb *lb, MsTy ty);
bool lb_is_fn(const Lb *lb, MirTy ty);
LbVal lb_lambda(Lb *lb, const MsExpr *e);
LbVal lb_function_value(Lb *lb, const MsExpr *e);
LbVal lb_call_value(Lb *lb, const MsExpr *e);
/* Lowers the queued lambdas after their maker; `ok` is whether the maker was lowered. */
bool lb_closures(Lb *lb, bool ok);

#define LB_FAIL ((LbVal){MIR_NONE, false})

#endif
