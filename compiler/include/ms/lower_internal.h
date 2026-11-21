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
    uint32_t row; /* the method row for a copy of a method of a generic type, else MS_NONE */
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
    const MsFunc *fn;    /* NULL for a module constant */
    MsExpr *value;       /* a module constant's initializer: the function of no parameters returns it */
    MsPos pos;
    uint32_t node;  /* the declaration (or method) node: `param_consumed`, `ret_borrowed` */
    MsSym name;     /* the MIR name, with the receiver's for a method */
    MsTy sig;       /* the signature, receiver not included */
    MsTy self_ty;   /* MS_TY_NONE for a function */
    bool mutating;  /* the receiver is a `var` one */
    bool consuming; /* the receiver is a `move` one */
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
    uint32_t file;        /* the module's source file in the output's file table (per pass) */
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

/* The function building the `Error` of a native's status table (lower_status.c). */
typedef struct LbStatusFn {
    MirTy error;
    bool said;
    const char *domain;
    uint32_t nrows;
    struct MsStatusRow *rows;
    uint32_t func;
} LbStatusFn;

/* A resource type with its own `close` (lower_close.c): its MIR type, the method row, and the helper
 * functions the elaborate pass runs, made on first use. */
typedef struct LbCloser {
    MirTy ty;
    uint32_t row;
    uint32_t func; /* the close of a generic type's copy, else MIR_NONE: the row's function */
    bool owned; /* a `move` close: it takes the value */
    uint32_t thunk, result;
    MsTy contract; /* an interface value that closes through its vtable (row MS_NONE), else MS_TY_NONE */
    uint32_t slot; /* its `close` operation's slot in the interface */
} LbCloser;

/* The function that returns a failed close as a function's own result, by what it is made for. */
typedef struct LbCloseExit {
    MirTy rty, ret;
    bool pending, borrowed;
    uint32_t func;
} LbCloseExit;

/* A local that lives in a stack slot the elaborate pass closes. */
enum { LB_MAX_MOVED = 4 };
typedef struct LbSlotLocal {
    uint32_t view, binding;
    MirValue slot;
    MirTy ty;
    uint32_t nmoved;                 /* resource fields that leave the local, each an owner of its own (lower_split.c) */
    uint32_t moved[LB_MAX_MOVED];    /* their field indexes */
    MirValue owner[LB_MAX_MOVED];    /* the address of each, which the scope closes unless the field left */
} LbSlotLocal;

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
    MsTy int_ty, float_ty, bool_ty, string_ty, void_ty, never_ty;
    /* By binding id: the value a `let` or parameter names, or the variable a `var` is. */
    MirValue *value_of;
    MirVar *var_of;
    uint32_t *func_of;    /* by symbol id: the module function a call reaches, or MIR_NONE */
    uint32_t *thunk_of;   /* by symbol id: the closure function forwarding to it, or MIR_NONE */
    LbJob *jobs;          /* the lambdas made by the function being lowered, to lower after it */
    uint32_t njobs, cjobs;
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE */
    LbCallable cur;       /* the function or method being lowered */
    uint32_t *method_func; /* by method row: the module function a method call reaches, or MIR_NONE */
    struct LbMethodRow *rows; /* by method row: the syntax of an impl method (method NULL for others) */
    /* The instance being lowered or stubbed: its function's variables and what they stand for. */
    const MsTy *sub_vars, *sub_args;
    uint32_t nsub;
    MsSym name_override; /* the instance's name, when `has_override` */
    LbInst *insts;        /* this pass's instances, in creation order (malloc) */
    uint32_t ninsts, cinsts;
    LbEq *eqs;            /* this pass's equality functions (module arena) */
    uint32_t neqs, ceqs;
    LbStatusFn *status_fns; /* this pass's status error functions (module arena) */
    uint32_t nstatus_fns, cstatus_fns;
    LbInst *dead_insts;         /* instances that failed in an earlier pass, kept across passes (malloc) */
    uint32_t ndead_insts, cdead_insts;
    LbCloser *closers;    /* this pass's resource types (module arena) */
    uint32_t nclosers, cclosers;
    LbCloseExit *exits;
    uint32_t nexits, cexits;
    LbSlotLocal *slots;   /* the resource locals of the function being lowered */
    uint32_t nslots, cslots;
    const MsStmt *stmt;   /* the statement being lowered: every instruction in it reports its position */
    MirTy *type_of;       /* by checker type: the record it lowered to, MIR_NONE, or LB_TYPE_PENDING while its fields lower */
    LbLoop *loop;         /* the innermost loop around the statement, or NULL */
    struct LbVarOwner *vars; /* the owned `var` Strings in scope, innermost last */
    uint32_t nvars, cvars;
    uint32_t *parts;      /* the bindings of owned payloads a match arm took out of its scrutinee: locals the arm owns */
    uint32_t nparts, cparts;
    MirValue *temps;      /* the owned temporaries of the statement being lowered, dropped where it ends (newest first) */
    uint32_t ntemps, ctemps;
    uint32_t stmt_mark;   /* `ntemps` where the statement being lowered began */
    int fail_line;
    uint32_t branching;   /* conditional contexts around the expression being lowered (an arm, a short-circuit's right side) */
    MsBuf *why;           /* NULL, or where each function that does not lower is listed (`ms_lower_program_why`) */
    const char *fail_site; /* the lowering source line that refused the function being lowered, when known */
    const MsStmt *fail_stmt; /* the statement being lowered then, or NULL */
    const MsExpr *iterable; /* the `for` iterable being lowered: a native call there yields a list the loop owns, never a view */
    bool closure;         /* lowering a closure body: no call depth, no `var` parameters */
    bool has_override;    /* `name_override` names the instance being lowered */
    bool first_pass;      /* the report lists the functions the checker did not record once, in the first pass */
    bool dead;            /* control cannot reach the current position */
    bool twin_ok;         /* the native call being marshalled is that iterable, so its base function (not a borrowing twin) is right */
    bool ok;              /* false once a construct outside the handled set is met */
} Lb;

/* lower_body.c: what the files that lower a construct call back into (`LB_UNSUPPORTED`, `lb_expr`
 * and `lb_mir_ty` are declared further down). */
void lb_statements(Lb *lb, const MsStmts *body);
void lb_return_void(Lb *lb);
uint32_t lb_scoped(Lb *lb, const MsStmts *body);          /* lowers `body` in its own scope; its owner depth */
MirBlock lb_step_block(Lb *lb, LbLoop *loop);             /* where `continue` of `loop` goes */
void lb_drop(Lb *lb, MirValue v);  /* releases an owned temporary */
MirValue lb_copy(Lb *lb, MirValue v); /* a borrowed String copied into a value the caller owns */
void lb_hold_temp(Lb *lb, MirValue v); /* an owned temporary that lives to the end of the statement */
MirLoc lb_loc(const Lb *lb, MsPos pos);
void lb_reset_state(Lb *lb);

/* Helpers of lower_body.c that lower_record.c and lower_method.c call. */
bool lb_owns(Lb *lb, MirTy ty);
MirValue lb_move_argument(Lb *lb, const MsExpr *e);
MirValue lb_load(Lb *lb, MirValue slot, MirTy ty);     /* reads a value from memory */
void lb_store(Lb *lb, MirValue slot, MirValue value);  /* writes a value to memory */
MsSym lb_unique_name(Lb *lb, MsStr base);              /* a function name not yet used in the module, from `base` */
/* Whether `ty` is a record, enum, optional or list: `==` on it and its text form call generated functions. */
static inline bool lb_is_aggregate(const Lb *lb, MirTy ty) {
    const uint8_t kind = mir_ty_data(lb->m, ty)->kind;
    return kind == MK_TYPE || kind == MK_ALT || kind == MK_OPT || kind == MK_LIST;
}
/* The parameters of a callable (lower_body.c) as lower_func.c reads them. */
bool lb_has_self(const LbCallable *c);
uint32_t lb_slots(const LbCallable *c);
const MsParam *lb_slot_param(const LbCallable *c, uint32_t slot);
bool lb_slot_mutable(const LbCallable *c, uint32_t slot);
uint32_t lb_slot_node(const LbCallable *c, uint32_t slot);
bool lb_param_moves(const Lb *lb, const LbCallable *c, uint32_t slot);
void lb_name_value(Lb *lb, MirValue value, MsSym name, bool param);
void lb_depth(Lb *lb, MirOp op);
/* The module function a call reaches (lower_func.c): the callee's own, or its copy for a generic one. */
uint32_t lb_instance(Lb *lb, MsSymId sym, const MsTy *args, uint32_t nargs);
uint32_t lb_method_instance(Lb *lb, uint32_t row, const MsTy *args, uint32_t nargs); /* a method of a generic type, for its arguments */
bool lb_lines_have_diagnostic(const MsModuleRow *row, uint32_t first, uint32_t end);
uint32_t lb_add_stub(Lb *lb, const LbCallable *c); /* a function with the signature and no body; MIR_NONE when not handled */
bool lb_function(Lb *lb, const LbCallable *c, uint32_t slot); /* lowers it over its stub; false when not handled */
/* A call of module function `func` of signature `sig`; `receiver` is the method receiver, else NULL. */
uint32_t lb_view_of(const Lb *lb, MsModId module); /* the view of `module`, or MS_NONE when it is not being lowered */
LbVal lb_call_func(Lb *lb, const MsExpr *e, uint32_t func, MsTy sig, const MsExpr *receiver, bool mutating);

/* Interface values (lower_iface.c, included after lower_body.c). */
MirTy li_type(Lb *lb, MsTy ty);
LbVal li_call(Lb *lb, const MsExpr *e);
/* The slot of the consuming `close() Void!` operation an interface declares (so a value of it closes through its
 * vtable), with the result type of the operation; false when it declares none. */
bool li_closer(Lb *lb, MsTy contract, uint32_t *slot, MirTy *result);
/* Frees the box of an interface value whose payload a consuming operation took. */
void li_free_box(MirBuilder *b, MirValue value);
LbVal li_box(Lb *lb, const MsExpr *e, LbVal value); /* a concrete value passed as an interface */

/* lower_method.c: methods of impls. */
bool lm_has(const Lb *lb, uint32_t row); /* a method this module wrote */
LbVal lm_call(Lb *lb, const MsExpr *e, uint32_t row);
uint32_t lm_instance(Lb *lb, uint32_t row, MsTy receiver); /* the copy of a generic type's method for `receiver`, or MIR_NONE */
LbCallable lm_callable(Lb *lb, uint32_t row);
bool lm_match(Lb *lb, uint32_t row, MsTy receiver, MsTy *args); /* the type arguments of row's impl for `receiver` */
void lb_why_unchecked(Lb *lb, MsSym name, MsPos pos, MsSite site); /* reports a function whose body the checker did not record */
enum { LA_OK = 0, LA_ERROR = 1 }; /* the order of the cases of `Result` in core.ms */
void lb_set_entry(Lb *lb, uint32_t user); /* makes `user`, the lowered `main`, the program's entry, behind a wrapper unless it returns Int (lower_entry.c) */
uint32_t lb_view_enter(Lb *lb, uint32_t view); /* reads module `view` from here on; returns the view it left */
uint32_t lm_prepare(Lb *lb);                                 /* the method rows of every view; their count */
void lm_stubs(Lb *lb, uint32_t nrows, const bool *failed);   /* a stub for each method to lower */
bool lm_lower(Lb *lb, uint32_t nrows, bool *failed, uint32_t *lowered);   /* true when one did not lower */

/* lower_close.c: resource locals closed by the elaborate pass. */
bool lc_has_closer(Lb *lb, MsTy ty);               /* a direct `close` of the type itself that does not change `self` */
void lc_register(Lb *lb, MsTy ty, MirTy mir);      /* the MIR type of a resource with one */
bool lc_bind(Lb *lb, const MsStmt *s, uint32_t binding, LbVal value); /* the local `binding` made from `value`; false when not handled */
bool lc_own_param(Lb *lb, uint32_t binding);        /* a `move` resource parameter the function closes; false when not handled */
bool lc_use(Lb *lb, uint32_t binding, MirValue *out, bool moved);  /* a read of a slot local */
bool lc_is_resource(Lb *lb, MirTy mir);               /* a registered resource type, owned even when it holds nothing to drop */
MirValue lc_slot_of(const Lb *lb, uint32_t binding);
bool lc_is_slot_local(const Lb *lb, uint32_t binding);
bool lc_exits_clean(const Lb *lb);
uint32_t lc_field_thunk(Lb *lb, MirTy field);       /* the function that closes a resource field in place, or MIR_NONE */
LbSlotLocal *lc_push_slot(Lb *lb, LbSlotLocal local);
/* lower_split.c: a resource field that a function moves out of a local it owns. */
uint32_t ls_moved_fields(Lb *lb, uint32_t binding, uint32_t *fields);
bool ls_own(Lb *lb, uint32_t binding, MirValue value, const uint32_t *fields, uint32_t nfields);
bool ls_has_resource_part(Lb *lb, MirTy record); /* a field of the record is a resource */
bool ls_owner_of(const Lb *lb, const MsExpr *member, MirValue *owner);
bool lc_is_closer_row(Lb *lb, uint32_t row);
void lc_check(Lb *lb);                             /* fails the function when it drops a resource */

/* lower_closure.c: function values and lambdas. */
MirTy lb_fn_ty(Lb *lb, MsTy ty);
bool lb_is_fn(const Lb *lb, MirTy ty);
LbVal lb_lambda(Lb *lb, const MsExpr *e);
/* `ty` seen through the generic instance being lowered: its type variables replaced by the type arguments. */
MsTy lb_ty(Lb *lb, MsTy ty);
LbVal lb_function_value(Lb *lb, const MsExpr *e);
void lb_at_expression(Lb *lb, const MsExpr *e);
int64_t lb_number_bits(Lb *lb, const MsExpr *e, MirTy ty, bool negate);
LbVal lb_call_value(Lb *lb, const MsExpr *e);
/* Lowers the queued lambdas after their maker; `ok` is whether the maker was lowered. */
bool lb_closures(Lb *lb, bool ok);

#define LB_FAIL ((LbVal){MIR_NONE, false})

/* Helpers of lower_body.c the files after it use. `LB_UNSUPPORTED` marks the function as not
 * handled and returns `LB_FAIL`. */
LbVal lb_unsupported_at(Lb *lb, const char *site, int line);
#define LB_UNSUPPORTED(lb) lb_unsupported_at((lb), __FILE__, __LINE__)
LbVal lb_expr(Lb *lb, const MsExpr *e);
/* `value`, the borrowed read of the place `e`, read again once the expressions after it were evaluated: one of them
 * may have replaced what the place holds (crates/ms-lower call.rs `refresh`). Other values are returned as they are. */
LbVal lb_refresh(Lb *lb, const MsExpr *e, LbVal value);
/* Whether `e` names a local or a field under one (`g`, `g.cells`): a place, which evaluating again only reads. */
bool lb_is_place(const Lb *lb, const MsExpr *e);
MirTy lb_mir_ty(Lb *lb, MsTy ty);
void lb_emit_plain(Lb *lb, MirOp op);
void lb_enter(Lb *lb, MirBlock block);
void lb_own_vars(Lb *lb, uint32_t depth, MirValue except);

void lb_write_back(Lb *lb);
LbVal lb_expr_plain(Lb *lb, const MsExpr *e);              /* lowers `e` without converting it to a plain value */
void lb_param_into_var(Lb *lb, uint32_t binding);        /* a handed-over parameter whose fields are assigned, as a `var` the function owns */
bool lb_is_pointer_param(Lb *lb, uint32_t binding);   /* a `var` record parameter: read and written through its pointer */
bool lb_var_owned(const Lb *lb, uint32_t binding);        /* whether the local `binding` owns what it holds */

/* Lists of scalars (lower_list.c, included after lower_body.c). */
MirTy lst_type(Lb *lb, MsTy ty);
bool lb_is_list(const Lb *lb, MirTy ty);
LbVal lst_literal(Lb *lb, const MsExpr *e);
LbVal lst_empty(Lb *lb, MirTy ty);
LbVal lst_index(Lb *lb, const MsExpr *e);
/* `list.get(index)` and `list.get_or(index, fallback)` of a list or Bytes: true when `e` is one (`out` is its value). */
bool lst_read_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out);
LbVal lst_get(Lb *lb, const MsExpr *left, const MsExpr *at);
void lst_for(Lb *lb, const MsStmt *s);
LbVal lb_native_method(Lb *lb, const MsExpr *e);
/* The local `var` a by-reference receiver names, else MS_NONE. */
uint32_t lb_var_receiver(Lb *lb, const MsExpr *receiver);
/* StringBuilder and BytesBuilder (lower_builder.c). */
bool lbd_is_builder(Lb *lb, MsTy ty);
LbVal lbd_new(Lb *lb);
bool lbd_method(Lb *lb, const MsExpr *e, LbVal *out);
const struct MsRtFn *lb_native_function(Lb *lb, MsTy receiver, MsSym method);
/* lower_extern.c: a call of a bodiless `extern fn`, by its own symbol in the ms-sig table. */
MirTy lx_type(Lb *lb, MsTy ty);
bool lx_is_extern(const Lb *lb, MsSymId callee);

/* lower_native.c: a native call that reports failure by a status. `out_ty` is the type of the value the call writes
 * through its `out` parameter (MIR_NONE when it writes none); `slots` returns the frame room for it and for the
 * failure text (MIR_NONE for an absent one). */
typedef struct LbNativeStatus {
    MirTy out_ty;
    bool found; // the call returns whether it wrote the value (a bool), not a status (an int)
} LbNativeStatus;
typedef struct LbNativeSlots {
    MirValue out;
    MirValue err;
} LbNativeSlots;
MirValue lb_native_status_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs,
                               const LbNativeStatus *status, LbNativeSlots *slots);

/* lower_out.c: the room a call's `out` pointer writes to, and the value taken from it after a successful call. */
MirValue lo_out_slot(Lb *lb, MirTy ty);
MirValue lo_take_out(Lb *lb, MirValue slot, MirTy ty);
LbVal lx_call(Lb *lb, const MsExpr *e, MsSymId callee);
/* lower_status.c: a native reporting failure by a status, called for a `Result[T, Error]`. */
bool ls_reports_status(Lb *lb, const struct MsRtFn *fn, MirTy result_ty);
LbVal ls_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty);
/* A native returning whether it found a value, written through an `out` scalar, called for an Optional of it. */
bool ls_reports_found(Lb *lb, const struct MsRtFn *fn, MirTy result_ty);
LbVal ls_found_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty);
LbVal lb_native_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty);

/* Whether `ty` is a plain scalar a closure captures and a map holds by value. */
static inline bool lb_is_scalar(MirTy ty) {
    return ty == MIR_INT || ty == MIR_FLOAT || ty == MIR_BOOL;
}

/* The runtime function that joins two strings, declared on first use. */
uint32_t lb_string_concat(Lb *lb);

MirTy lm_type(Lb *lb, MsTy ty);
bool lb_is_map(const Lb *lb, MirTy ty);
bool lb_is_set(const Lb *lb, MirTy ty);
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
LbVal lt_single(Lb *lb, const MsExpr *hole);
LbVal lt_scalar_text(Lb *lb, MsTy checked, MirValue v);
LbVal lt_to_string(Lb *lb, LbVal value, MsTy checked);
uint32_t lt_runtime_extern(Lb *lb, const MirExtern *want);

/* Structural text of a record or enum (lower_format.c, included after lower_text.c). */
LbVal lf_text(Lb *lb, LbVal value);
/* Converts the number `x` to `checked_result` (a number, or an Optional integer); false when this does not lower. */
/* Whether the method `name` is spelled as a conversion to a primitive type: `to_int16`, `to_float`. */
bool lb_is_conversion_name(const Lb *lb, MsSym name);
bool lb_numeric_conversion(Lb *lb, MirValue x, MsTy checked_result, LbVal *out);
/* `abs` or `sign` of an `Int`: true when `e` is one (`out` is its value), false before anything is lowered. */
bool lb_int_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out);
/* lower_optional.c: methods that are instructions. Each returns whether the call is one of its methods and sets `out`. */
bool lb_optional_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out); /* `get_or` of an Optional */
/* lower_each.c: `map` and `filter` of a list, a loop that calls the function value on each element. */
bool lb_each_method(Lb *lb, const MsExpr *e, MsTy receiver_ty, LbVal *out);
bool lb_clone_method(Lb *lb, const MsExpr *e, LbVal *out);                      /* `clone` of a value no runtime function copies */

/* User enums (lower_enum.c, included after lower_body.c). */
MirTy le_type(Lb *lb, MsTy ty);

/* Records (lower_record.c, included after lower_body.c). */
MirTy lr_type(Lb *lb, MsTy ty);
LbVal lr_construct(Lb *lb, const MsExpr *call);
MsTy le_field_ty(Lb *lb, const MsDef *def, MsTy ty, MsTy declared);
LbVal lm_empty(Lb *lb, MirTy ty);
LbVal lr_field(Lb *lb, const MsExpr *e);
void lr_assign_field(Lb *lb, const MsStmt *s);

/* Optional and Result (lower_alt.c, included after lower_body.c). */
MirTy la_type(Lb *lb, MsTy ty);
LbVal la_none(Lb *lb, const MsExpr *e);
LbVal la_nullary(Lb *lb, const MsExpr *e);
MirValue la_ok_unit(Lb *lb);
bool la_returns_void_result(const Lb *lb); /* the function being lowered returns `Void!` */
MirValue la_ok_of(Lb *lb, MirValue unit);     /* `ok(unit)` of that result */
LbVal la_none_owned(Lb *lb, const MsExpr *e);
LbVal la_case(Lb *lb, const MsExpr *call);
MirValue la_test(Lb *lb, MirValue subject);
MirValue la_payload(Lb *lb, MirValue subject, bool borrowed);
LbVal la_fallback(Lb *lb, const MsExpr *e); /* `x.get_or(default)` */
MirValue la_take_ok(Lb *lb, MirValue subject); /* an owned Result's Ok value, moved out of it */
LbVal la_try(Lb *lb, const MsExpr *e);

#endif
