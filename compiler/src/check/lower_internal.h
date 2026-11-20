/* Shared state of the body lowering (lower_body.c) and the files that lower one kind of value
 * for it (lower_record.c). `Lb` is the function being lowered; a file adds its own hook
 * (`lr_*` records) and lower_body.c calls it where it dispatches on the expression kind. */
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
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE */
    const MsDecl *decl;   /* the function being lowered */
    const MsStmt *stmt;   /* the statement being lowered: every instruction in it reports its position */
    MirTy *type_of;       /* by checker type: the record it lowered to, or MIR_NONE */
    LbLoop *loop;         /* the innermost loop around the statement, or NULL */
    struct LbVarOwner *vars; /* the owned `var` Strings in scope, innermost last */
    uint32_t nvars, cvars;
    bool dead;            /* control cannot reach the current position */
    bool ok;              /* false once a construct outside the handled set is met */
} Lb;

#define LB_FAIL ((LbVal){MIR_NONE, false})

static inline LbVal lb_unsupported(Lb *lb) {
    lb->ok = false;
    return LB_FAIL;
}

/* Shared helpers of lower_body.c. */
MirTy lb_mir_ty(Lb *lb, MsTy ty);
LbVal lb_expr(Lb *lb, const MsExpr *e);
MirLoc lb_loc(const Lb *lb, MsPos pos);

/* Records (lower_record.c). */
MirTy lr_type(Lb *lb, MsTy ty);
LbVal lr_construct(Lb *lb, const MsExpr *call);
LbVal lr_field(Lb *lb, const MsExpr *e);

#endif
