/* The state shared by the files of the body lowering (lower_body.c and the files it hands
 * constructs to). The lowering is one translation unit (libms.c): helpers stay `static` in their
 * file and are visible to the files included after it; a construct a later file lowers is
 * declared here and called from lower_body.c. Prefix: `lb_`. */
#ifndef MS_LOWER_INTERNAL_H
#define MS_LOWER_INTERNAL_H

#include "ms/check.h"
#include "ms/ownership.h"
#include "ms/facts.h"
#include "ms/lower_scope.h"
#include "ms/mir_builder.h"

/* The loop being lowered: where `continue` and `break` go. Lives on the lowering's stack. A
 * `for` has a step block that only exists once something branches to it. */
/* `type_of` of a record whose fields are being lowered: reaching it again means the record holds itself. */
#define LB_TYPE_PENDING (MIR_NONE - 1)

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

/* One copy of a generic function: the type arguments it was made for, in the order of the
 * function's variables. */
#define LB_MAX_TARGS 8
typedef struct LbInst {
    MsSymId sym;
    uint32_t nargs;
    MsTy args[LB_MAX_TARGS];
    uint32_t func; /* its module function; MIR_NONE once it failed */
} LbInst;

/* A lambda whose closure function is added but not yet lowered: `func` is its stub and `caps`
 * the outer bindings its environment holds, in order. */
typedef struct LbJob {
    const MsExpr *lambda;
    uint32_t func;
    uint32_t *caps;
    uint32_t ncaps;
    bool *by_ref; /* by capture: the environment holds a pointer to the local, which the closure reads in place */
} LbJob;

/* A function or method being lowered: its syntax, the node its facts hang on, its signature, and
 * the receiver a method takes as parameter 0. */
typedef struct LbCallable {
    const MsFunc *fn;
    uint32_t node;  /* the declaration (or method) node: `param_consumed`, `ret_borrowed` */
    MsPos pos;
    MsSym name;     /* the MIR name, with the receiver's for a method */
    MsTy sig;       /* the signature, receiver not included */
    MsTy self_ty;   /* MS_TY_NONE for a function */
    bool mutating;  /* the receiver is a `var` one */
} LbCallable;

/* What the lowering reads of one source module: its facts, and the tables its node and binding ids
 * index. A body is lowered with its own module's view entered (`lb_view_enter`). */
typedef struct LbView {
    MsModId module;
    const MsFacts *facts;
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE (output arena, per pass) */
    MirValue *value_of;   /* by binding id (output arena, per pass) */
    MirVar *var_of;       /* by binding id (output arena, per pass) */
    bool *failed;         /* by declaration: it did not lower in an earlier pass (malloc) */
} LbView;

/* An impl method a lowered module wrote: its row, where it starts, and the source lines it owns. */
typedef struct LbMethodRow {
    const MsMethod *method; /* NULL for a row no method of the lowered modules carries */
    uint32_t view;          /* the view of the module that wrote it */
    MsPos owner_pos;        /* where the impl declaration starts: the method's location in MIR */
    uint32_t first_line, end_line;
} LbMethodRow;

/* The function comparing two values of `ty`, or MIR_NONE when `ty` cannot be compared (lower_eq.c). */
typedef struct LbEq {
    MirTy ty;
    uint32_t func;
} LbEq;

typedef struct Lb {
    MsClassifier *classifier; /* classes of types: a value that closes is left to the Rust lowering */
    const MsCheck *c;
    LbView *views;  /* the modules being lowered into `m` (malloc) */
    uint32_t nviews;
    uint32_t view;  /* the entered view: `module`, `facts`, `binding_at`, `value_of` and `var_of` are its */
    MsModId module; /* the module whose body is being lowered */
    MsCheck *mut; /* the same table, for `ms_def`, which adds rows on demand */
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
    LbCallable cur;       /* the function or method being lowered */
    uint32_t *method_func; /* by method row: the module function a method call reaches, or MIR_NONE */
    struct LbMethodRow *rows; /* by method row: the syntax of an impl method (method NULL for others) */
    /* The instance being lowered or stubbed: its function's variables and what they stand for. */
    const MsTy *sub_vars, *sub_args;
    uint32_t nsub;
    MsSym name_override; /* the instance's name, when `has_override` */
    bool has_override;
    LbInst *insts;        /* this pass's instances, in creation order (malloc) */
    uint32_t ninsts, cinsts;
    LbEq *eqs;            /* this pass's equality functions (module arena) */
    uint32_t neqs, ceqs;
    LbInst *dead_insts;         /* instances that failed in an earlier pass, kept across passes (malloc) */
    uint32_t ndead_insts, cdead_insts;
    const MsStmt *stmt;   /* the statement being lowered: every instruction in it reports its position */
    MirTy *type_of;       /* by checker type: the record it lowered to, MIR_NONE, or LB_TYPE_PENDING while its fields lower */
    LbLoop *loop;         /* the innermost loop around the statement, or NULL */
    struct LbVarOwner *vars; /* the owned `var` Strings in scope, innermost last */
    uint32_t nvars, cvars;
    MirValue *temps;      /* the owned temporaries of the statement being lowered, dropped where it ends (newest first) */
    uint32_t ntemps, ctemps;
    uint32_t stmt_mark;   /* `ntemps` where the statement being lowered began */
    uint32_t branching;   /* conditional contexts around the expression being lowered (an arm, a short-circuit's right side) */
    bool dead;            /* control cannot reach the current position */
    bool ok;              /* false once a construct outside the handled set is met */
} Lb;

/* lower_body.c: what the files that lower a construct call back into (`lb_unsupported`, `lb_expr`
 * and `lb_mir_ty` are declared further down). */
void lb_statements(Lb *lb, const MsStmts *body);
void lb_return_void(Lb *lb);
uint32_t lb_scoped(Lb *lb, const MsStmts *body);          /* lowers `body` in its own scope; its owner depth */
MirBlock lb_step_block(Lb *lb, LbLoop *loop);             /* where `continue` of `loop` goes */
void lb_drop(Lb *lb, MirValue v);  /* releases an owned temporary */
void lb_hold_temp(Lb *lb, MirValue v); /* an owned temporary that lives to the end of the statement */
MirLoc lb_loc(const Lb *lb, MsPos pos);
void lb_reset_state(Lb *lb);

/* Helpers of lower_body.c that lower_record.c and lower_method.c call. */
bool lb_owns(Lb *lb, MirTy ty);
MirValue lb_move_argument(Lb *lb, const MsExpr *e);
MirValue lb_load(Lb *lb, MirValue slot, MirTy ty);     /* reads a value from memory */
void lb_store(Lb *lb, MirValue slot, MirValue value);  /* writes a value to memory */
bool lb_lines_have_diagnostic(const MsModuleRow *row, uint32_t first, uint32_t end);
uint32_t lb_add_stub(Lb *lb, const LbCallable *c); /* a function with the signature and no body; MIR_NONE when not handled */
bool lb_function(Lb *lb, const LbCallable *c, uint32_t slot); /* lowers it over its stub; false when not handled */
/* A call of module function `func` of signature `sig`; `receiver` is the method receiver, else NULL. */
LbVal lb_call_func(Lb *lb, const MsExpr *e, uint32_t func, MsTy sig, const MsExpr *receiver, bool mutating);

/* Interface values (lower_iface.c, included after lower_body.c). */
MirTy li_type(Lb *lb, MsTy ty);
LbVal li_call(Lb *lb, const MsExpr *e);
LbVal li_box(Lb *lb, const MsExpr *e, LbVal value); /* a concrete value passed as an interface */

/* lower_method.c: methods of impls. */
bool lm_has(const Lb *lb, uint32_t row); /* a method this module wrote */
LbVal lm_call(Lb *lb, const MsExpr *e, uint32_t row);
uint32_t lb_view_enter(Lb *lb, uint32_t view); /* reads module `view` from here on; returns the view it left */
uint32_t lm_prepare(Lb *lb);                                 /* the method rows of every view; their count */
void lm_stubs(Lb *lb, uint32_t nrows, const bool *failed);   /* a stub for each method to lower */
bool lm_lower(Lb *lb, uint32_t nrows, bool *failed, uint32_t *lowered);   /* true when one did not lower */

/* lower_closure.c: function values and lambdas. */
MirTy lb_fn_ty(Lb *lb, MsTy ty);
bool lb_is_fn(const Lb *lb, MirTy ty);
LbVal lb_lambda(Lb *lb, const MsExpr *e);
LbVal lb_function_value(Lb *lb, const MsExpr *e);
LbVal lb_call_value(Lb *lb, const MsExpr *e);
/* Lowers the queued lambdas after their maker; `ok` is whether the maker was lowered. */
bool lb_closures(Lb *lb, bool ok);

#define LB_FAIL ((LbVal){MIR_NONE, false})

/* Helpers of lower_body.c the files after it use. `lb_unsupported` marks the function as not
 * handled and returns `LB_FAIL`. */
LbVal lb_unsupported(Lb *lb);
LbVal lb_expr(Lb *lb, const MsExpr *e);
MirTy lb_mir_ty(Lb *lb, MsTy ty);
void lb_emit_plain(Lb *lb, MirOp op);
void lb_enter(Lb *lb, MirBlock block);
void lb_own_vars(Lb *lb, uint32_t depth, MirValue except);
void lb_write_back(Lb *lb);
LbVal lb_expr_plain(Lb *lb, const MsExpr *e);              /* lowers `e` without converting it to a plain value */
bool lb_var_owned(const Lb *lb, uint32_t binding);        /* whether the local `binding` owns what it holds */

/* Lists of scalars (lower_list.c, included after lower_body.c). */
MirTy lst_type(Lb *lb, MsTy ty);
bool lb_is_list(const Lb *lb, MirTy ty);
LbVal lst_literal(Lb *lb, const MsExpr *e);
LbVal lst_index(Lb *lb, const MsExpr *e);
void lst_for(Lb *lb, const MsStmt *s);
LbVal lb_native_method(Lb *lb, const MsExpr *e);
const struct MsRtFn *lb_native_function(Lb *lb, MsTy receiver, MsSym method);
LbVal lb_native_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty);
/* Stores `value` in the stack slot `slot`. */

/* Whether `ty` is a plain scalar a closure captures and a map holds by value. */
static inline bool lb_is_scalar(MirTy ty) {
    return ty == MIR_INT || ty == MIR_FLOAT || ty == MIR_BOOL;
}

/* The runtime function that joins two strings, declared on first use. */
uint32_t lb_string_concat(Lb *lb);

MirTy lm_type(Lb *lb, MsTy ty);
bool lb_is_map(const Lb *lb, MirTy ty);
LbVal lm_literal(Lb *lb, const MsExpr *e);
LbVal lm_index(Lb *lb, LbVal map, const MsExpr *at);
struct MsRtFn;
/* The runtime function `name` over these borrowed parameters, declared once per signature. */
uint32_t lb_runtime_extern(Lb *lb, const char *name, const MirTy *params, uint32_t nparams, MirTy ret, uint8_t role,
                           bool reads);
/* The entry of `generic` that fits a map of `key` and `value` (its declared specialisation, else itself). */
const struct MsRtFn *lm_specialize(Lb *lb, const struct MsRtFn *generic, MirTy key, MirTy value, uint8_t *role);

/* Equality of records, enums, optionals and lists (lower_eq.c, included after lower_closure.c). */
LbVal lq_equal(Lb *lb, LbVal x, LbVal y, bool negate);

/* Strings built from pieces (lower_text.c, included after lower_body.c). */
LbVal lt_text(Lb *lb, const MsExpr *e);
LbVal lt_scalar_text(Lb *lb, MsTy checked, MirValue v);
uint32_t lt_runtime_extern(Lb *lb, const MirExtern *want);

/* Structural text of a record or enum (lower_format.c, included after lower_text.c). */
LbVal lf_text(Lb *lb, LbVal value);

/* User enums (lower_enum.c, included after lower_body.c). */
MirTy le_type(Lb *lb, MsTy ty);

/* Records (lower_record.c, included after lower_body.c). */
MirTy lr_type(Lb *lb, MsTy ty);
LbVal lr_construct(Lb *lb, const MsExpr *call);
LbVal lm_empty(Lb *lb, MirTy ty);
LbVal lr_field(Lb *lb, const MsExpr *e);

/* Optional and Result (lower_alt.c, included after lower_body.c). */
MirTy la_type(Lb *lb, MsTy ty);
LbVal la_none(Lb *lb, const MsExpr *e);
LbVal la_nullary(Lb *lb, const MsExpr *e);
LbVal la_none_owned(Lb *lb, const MsExpr *e);
LbVal la_case(Lb *lb, const MsExpr *call);
MirValue la_test(Lb *lb, MirValue subject);
MirValue la_payload(Lb *lb, MirValue subject);
LbVal la_try(Lb *lb, const MsExpr *e);

#endif
