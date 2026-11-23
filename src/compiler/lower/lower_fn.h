/* compiler/lower/lower_fn.h: the state of the function being lowered, and what its statement, expression and
 * call code share. */
#ifndef MS_COMPILER_LOWER_LOWER_FN_H
#define MS_COMPILER_LOWER_LOWER_FN_H

#include "compiler/lower/lower_internal.h"

/* How the consumer takes an expression's value: it reads it in place, or it takes ownership. */
typedef enum LowerWant { LW_BORROW, LW_MOVE } LowerWant;


/* A `var` local that owns its current value: the scope that declared it owns that value where the scope ends. */
typedef struct LowerOwnedVar {
  uint32_t scope;
  MirVar var;
  uint32_t moved; /* the fields of a record the variable has handed on, as a bit mask */
  MsTy checked;   /* the record's checked type once a field moved, so the scope end can close the fields left */
  MirVar mask;    /* the fields handed on along the path taken, as a bit mask; a record's variable only */
  bool has_mask;
  bool leaves;    /* a record whose fields the body hands on: an exit before the first move closes the fields it still holds */
  uint32_t partial; /* fields of the record that handed a part of their own on (`record.field.part`); also in `moved` */
  uint64_t nbits;   /* the parts handed on, bit `field * 8 + part` */
  MirVar nmask;     /* the parts handed on along the path taken, same layout; a record that holds a record field only */
  bool has_nmask;
  MsTy inner[8];    /* the checked type of each partial field */
  bool released;  /* a return is handing the whole value on: the unwind it starts must not own it */
  MirValue pinned; /* the value an inner scope's end owns for it while a close failure may leave the function, else MIR_NONE */
} LowerOwnedVar;

/* Where `break` and `continue` go, and how many scopes were open outside the loop. */
typedef struct LowerLoop {
  MirBlock break_to, continue_to;
  uint32_t depth;
} LowerLoop;

/* A `var` parameter: the callee takes its value out of the caller's slot at entry and puts it back at every return. */
typedef struct LowerVarParam {
  MirVar var;
  MirValue slot;
  MirTy ty;
} LowerVarParam;

/* The per-local tables of a function, set aside while the default argument of a callee (whose locals are numbered in
 * that callee) is lowered with tables of its own. */
typedef struct LowerFnLocals {
  MirVar *vars;
  uint8_t *local_owns;
  MirValue *closing;
  bool *closing_var;
  uint8_t *shared;
  bool *holds_value;
  MirTy *closing_types;
  uint32_t nvars;
} LowerFnLocals;
/* The environment a call's caller lowered in, set aside while the default argument of a callee is lowered in the
 * callee's: what a writeback registered by the caller needs to put its value back from inside the default. */
typedef struct LowerOuterEnv {
  const MsFacts *facts;
  uint32_t module_index;
  uint32_t file;
  LowerSubst subst;
  LowerFnLocals locals;
  const MsCall *default_call;
  MirValue *default_args;
  const MsParams *default_params;
  bool default_has_self;
} LowerOuterEnv;

/* An `if var name = place[key]?` binding: the variable is a copy of the entry's bits, stored back to `address` wherever
 * the body is left. `depth` is the number of scopes open inside the body. */
typedef struct LowerWriteback {
  MirVar var;
  MirValue address;
  MirTy ty;
  uint32_t depth;
  uint32_t env; /* how many default arguments were being lowered when it was registered */
  struct VarSlot *lent; /* a `for` over a variable: the slot the iterator was lent in, which goes back to its place */
} LowerWriteback;

enum { LOWER_MAX_CLOSING_PARAMS = 32 };

/* The exit of a call whose default argument uses `?`: the error leaves the call as its result, not the caller (lower_call.c). */
typedef struct DefaultExit {
  MirBlock join; /* the block the call's result, or the failed Result, flows to */
  uint32_t keep; /* the scopes open outside the call: the exit ends the ones the call opened */
  MirTy ret;     /* the call's result type, the type of the failed Result */
} DefaultExit;

typedef struct LowerFn {
  Lower *cx;
  MirBuilder b;
  const MsFacts *facts;
  const MsFunc *func;
  /* Index keys of a `var` place evaluated early, in written order: the place's later uses read these, not the keys again. */
  struct { const MsExpr *expr; MirValue value; } presolved[8];
  uint32_t npresolved;
  bool keeps_scoped; /* this function keeps the closures it is given (the flag of its MIR function) */
  uint32_t module_index;
  uint32_t file; /* the MIR file id of the module */
  MirLoc stmt_loc; /* the statement being lowered: what `caller_site()` names */
  LowerSubst subst;
  MirVar *vars;       /* by checker local id */
  uint8_t *local_owns; /* by checker local id: 1 bound to a value this function's scope owns, 2 a view of what another owner holds (NULL: none known) */
  MirValue *closing;  /* the slot a closed resource lives in, else MIR_NONE: by local id, then by parameter index */
  bool *closing_var;  /* the same index: the binding is `var`, so every read loads the slot */
  MirValue default_base; /* a field default: the address of the record being built, whose earlier fields it reads */
  MirTy default_record_ty;
  uint32_t shared_params; /* bit i: a lambda changes the `var` parameter i */
  uint8_t *shared;      /* by local id: a lambda changes it, so it lives in a slot (the closing machinery) */
  bool *holds_value;    /* by local id: a field of the local is moved out, so it stays a variable that keeps the mask of what is left */
  uint32_t cell_old_at;  /* local + 1 while `x = rhs` is lowered: the cell of `x` has given its value up, and `rhs` reads it as `cell_old` */
  MirValue cell_old;
  MirTy *closing_types; /* the same index: the type of the value in the slot */
  uint32_t nvars;
  MirVar *param_vars; /* by parameter index */
  const DefaultExit *call_exit;    /* the call being lowered, when its defaults can exit it */
  const DefaultExit *default_exit; /* while such a default is lowered: where its `?` leaves to */
  const MsCall *default_call; /* while a default argument is lowered: the call, whose parameters the default may read */
  MirValue *default_args; /* ... and the values of its arguments so far, by parameter index (MIR_NONE: not yet) */
  LowerSubst default_vars; /* ... and the method's type variables as the value was bound */
  const MsParams *default_params; /* a call of a lambda or method value: the parameters whose defaults it leaves out */
  bool default_has_self; /* a call of a method value: `default_self` is the receiver a default reads as `self` (the call's arguments omit it) */
  MirValue default_self;
  struct { uint32_t local; MirValue receiver; const MsParams *params; LowerSubst vars; } bound_self[8]; /* locals bound to a lambda or method value: its parameters, and the receiver it captured (MIR_NONE: none) */
  uint32_t nbound_self;
  LowerSubst last_vars; /* the type variables of the method value just lowered, bound */
  MirValue last_receiver; /* the receiver of the method value just lowered */
  bool has_last_receiver;
  MirTy ret;
  MsTy ret_checked; /* the checked result type of a named function (MS_TY_NONE for a lambda): a pending result closes through it */
  uint32_t next_scope;               /* the next scope id to hand out */
  uint32_t *open;   /* the scopes open now, outermost first (grown in the module arena) */
  bool *open_closes; /* whether the scope at that depth owns a slot that closes where it ends */
  uint32_t nopen, open_cap;
  LowerOwnedVar *owned_vars;
  uint32_t nowned_vars, owned_vars_cap;
  MirValue moved_names[8]; /* values a name read handed on, in the statement being lowered: an assignment does not drop them */
  uint32_t nmoved_names;
  const MsExpr *placing_member; /* the receiver a native takes out of its place itself: reading it leaves it there */
  const MsExpr *taking_member; /* the member read whose value the consumer takes (LW_MOVE) */
  bool read_moves;             /* the expression being read hands its value to a consumer (LW_MOVE) */
  const MsExpr *narrow_take;   /* the narrowed local whose payload the reader takes, as a field moves out of it */
  const MsExpr *or_view;        /* the `x or d` a field read looks through: its payload may stay a view of `x` */
  const MsExpr *moving_field; /* the field read of a `name := record.field` bind whose field the callable assigns next */
  const MsExpr *moved_fields[4]; /* fields moved out of a `var` record and not yet assigned: the assignment drops nothing */
  uint32_t nmoved_fields;
  LowerVarParam *var_params;
  uint32_t nvar_params, var_params_cap;
  MirVar refilling_var; /* plus one: the `var` parameter an assignment to it is refilling, whose value the right side may take */
  LowerWriteback *writebacks;
  uint32_t nwritebacks, writebacks_cap;
  LowerOuterEnv *outer; /* the environments of the calls whose defaults are being lowered, outermost first */
  uint32_t nouter, outer_cap;
  bool failed;
  bool returns_view; /* the result is a view lender's owned box of an interface that borrows: a returned reference is boxed by `iface.own` */
  bool returns_borrow; /* the function's result borrows from a parameter: `return` hands back the reference, no copy */
  MirTy comparing[8]; /* the records and alternatives whose equality is being written out, innermost last */
  uint32_t ncomparing;
  MirTy hint; /* the type a default expression is wanted as, for an expression the checker left untyped */
  bool decl_void; /* declared to return Void, though the MIR function returns an Int status (the entry) */
  bool terminated;
  MirValue receiver_slot; /* a native call's fresh receiver, in the closing slot its arguments were evaluated after (MIR_NONE: none) */
  uint32_t native_arg_moves; /* the source operands of the native call that its declaration takes (`move`) */
  MirTy native_value_ty; /* the element or value type of the collection the native being called reads, else MIR_NONE */
  uint32_t native_moves; /* the operands of the runtime call being built that the runtime takes, by position */
  bool temps; /* a statement scope is open for the temporaries its calls borrow */
  const MsStmt *sink_stmt; /* a bench body's last statement: when it is a call, its value goes to the bench sink */
  uint32_t bind_scope; /* with `temps` on a bind: the scope the name it binds belongs to, plus one; zero when none */
  uint32_t nloops;
  LowerLoop *loops; /* the loops open now, outermost first */
  uint32_t loops_cap;
  const LowerLambda *lambda; /* the lambda whose body this is, or NULL */
  MirVar *cap_vars;           /* a lambda body: the variable holding each capture */
  uint32_t local_count; /* the current block ended in a return: the statements after it are unreachable */
} LowerFn;

/* Room for one more element of a per-function table (module arena memory): the tables are bounded only by memory. */
void *fn_grow(LowerFn *fn, void *items, uint32_t *cap, uint32_t used, size_t size);

/* Opens a loop for `break` and `continue`; nesting is bounded only by memory. */
void fn_loop_push(LowerFn *fn, MirBlock break_to, MirBlock continue_to);

LowerFnLocals fn_locals_save(const LowerFn *fn);
/* Replaces the tables with empty ones for `nvars` locals (closing slots included). */
void fn_locals_fresh(LowerFn *fn, uint32_t nvars);
void fn_locals_restore(LowerFn *fn, const LowerFnLocals *saved);
/* The environment now in force, and putting one back: a writeback registered outside a default argument runs in its own. */
LowerOuterEnv fn_env_capture(const LowerFn *fn);
void fn_env_install(LowerFn *fn, const LowerOuterEnv *env);

#define fn_fail(fn, ...) ((fn)->failed = true, lower_fail((fn)->cx, __VA_ARGS__))
#define fn_user_fail(fn, ...) ((fn)->failed = true, lower_user_fail((fn)->cx, __VA_ARGS__))

/* ---- scopes (lower_scope.c) ---- */

/* A function in the first module's facts for the reserved MIR function `reserved`, with its outermost scope open: the
 * start of a generated function (glue, hooks) that has no source of its own. */
LowerFn fn_begin_reserved(Lower *cx, const MirFunc *reserved);
/* Opens a scope inside the current one and returns its id. */
uint32_t fn_scope_begin(LowerFn *fn);
/* Closes the innermost scope: its owners are dropped or closed where it ends. */
void fn_scope_end(LowerFn *fn);
void fn_scope_pop(LowerFn *fn);
/* Emits the `scope.end` of every open scope from the innermost down to (not including) depth `keep`, without
 * popping them: the code after it leaves the function or the loop. */
void fn_scope_unwind(LowerFn *fn, uint32_t keep);
/* The innermost open scope. */
uint32_t fn_scope(const LowerFn *fn);
/* Registers `var`, which holds an owned value that is not owned by any scope, with the innermost scope. `leaves` is the
 * checked type of a record the body hands fields of on (MS_TY_NONE otherwise). */
bool fn_scope_own_var(LowerFn *fn, MirVar var, MsTy leaves);
/* The variable a name place assigns to: a `var` local or a `var` parameter; false for any other place. */
bool fn_owned_local(LowerFn *fn, const MsExpr *place, MirVar *out);
/* The variable handed field `field` of its record on: its scope releases only the fields it still holds. */
void fn_scope_var_moved(LowerFn *fn, MirVar var, uint32_t field, MsTy checked);
/* The variable handed part `part` of its field `field` on (`name.field.part`): the field's other parts stay with it. */
bool fn_scope_var_moved_part(LowerFn *fn, MirVar var, uint32_t field, uint32_t part, MsTy checked, MsTy field_type);
/* The parts of record fields handed on, for `fn_close_left_fields`: `partial` fields, their `bits` and the `flag` of the
 * parts handed on along this path (bit `field * 8 + part`), and the checked type of each partial field. */
typedef struct LowerPartMoves {
  uint32_t partial;
  uint64_t bits;
  MirValue flag;
  const MsTy *inner;
} LowerPartMoves;
/* Settles what the record `value` (of checked type `record`) still holds, last field first: a resource field closes,
 * and a field that only owns memory drops when it is one of `maybe` (the fields handed on along some path, whose
 * `flag` bit says whether this path did). `taken` fields are gone already. Returns `taken` with the fields handled
 * added, which the record's release then skips. */
uint32_t fn_close_left_fields(LowerFn *fn, MirValue value, MsTy record, uint32_t taken, const MirVar *owner, uint32_t maybe,
                              MirValue flag, const LowerPartMoves *parts);
void fn_scope_var_released(LowerFn *fn, MirVar var, bool released);
/* The descriptor a native's signature names (`kind` is NS_ELEM_DESC, NS_KEY_DESC or NS_VAL_DESC) of the first collection among `args`. */
bool fn_is_list(LowerFn *fn, const MsExpr *expr);
MirValue fn_native_scalar(LowerFn *fn, MirValue operand);
bool fn_descriptor_argument(LowerFn *fn, uint8_t kind, const MirValue *args, uint32_t nargs, MirValue *out);
/* The field `expr` (field number `index`) of an owned variable (`name.field`) or of one of its fields (`name.field.part`)
 * leaves it: records the move; false when the record is not an owned variable. */
bool fn_move_field(LowerFn *fn, const MsExpr *expr, uint32_t index);
/* Whether the body hands fields of the record local `local` (of MIR type `ty`) on, so a variable owns it. */
bool fn_leaves_fields(const LowerFn *fn, uint32_t local, MirTy ty);
bool fn_take_field(LowerFn *fn, const MsExpr *place, MirValue *record, MirValue *field);
bool fn_put_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field);
bool fn_put_field_chain(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field, MirValue *updated_record, bool store);
bool fn_read_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue *field);
bool fn_same_field_root(LowerFn *fn, const MsExpr *a, const MsExpr *b);
bool fn_same_member_path(LowerFn *fn, const MsExpr *a, const MsExpr *b);
/* The slot a closing `var` local or parameter lives in. */
bool fn_closing_param(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirVar *var);
bool fn_closing_local(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirTy *ty);
/* `value` as an owned copy the scope no longer owns (a clone unless it is fresh). */
MirValue fn_move_out_of_scope(LowerFn *fn, MirValue value);
/* The payload of the optional `opt`, or `fallback` evaluated when it is none: the value of a parameter a function value
 * may leave out. The result is owned when its type needs a drop. */
MirValue fn_unlift(LowerFn *fn, MirValue opt, const MsExpr *fallback, MirTy elem);
/* Makes the scope `scope` own `value` (kind 0 drops it). */
void fn_own(LowerFn *fn, uint32_t scope, MirValue value);

/* Emits an instruction; when its result is an owned value the innermost scope owns it. */
MirValue fn_emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty);
/* A copy the source did not ask for (`.clone()` is the only explicit one): a borrowed value an owner takes. Every such
 * copy goes through here so the rule against hidden copies has one place to be enforced; `own` makes the scope own it. */
MirValue fn_implicit_clone(LowerFn *fn, MirValue value, bool own);
/* Makes the innermost scope own `result`, the result of the instruction just emitted, when it is owned. */
void fn_own_result(LowerFn *fn, MirValue result);

/* Whether `value` is the owned result of the instruction just emitted, held by the innermost scope. */
/* Whether `value` is the result of the instruction just emitted and a borrowed view of something that owns it. */
bool fn_is_borrowed_view(LowerFn *fn, MirValue value);
bool fn_fresh_owner(LowerFn *fn, MirValue value);
/* Whether `value` is a result the caller owns: `fn_fresh_owner` for a type with heap parts, and for a flat one (a
 * resource record of integers) not a view of an element or field that its collection or record still owns. */
bool fn_owns_result(LowerFn *fn, MirValue value);
/* lower_temp.c: `list` is the call result `index` reads an element from: it closes with the statement. */
MirValue fn_closing_indexed(LowerFn *fn, const MsExpr *index, MirValue list);

/* ---- resources closed at scope end (lower_close.c) ---- */

/* Whether lowering closes a binding with this closer (NULL for none), of checker type `checked`: a `move fn close`
 * that no use closes by hand, changes in place or splits. */
bool fn_closer_for(LowerFn *fn, const MsCloser *closer, MsTy checked);
/* As `fn_closer_for` for a parameter, whose slot an assignment into its fields takes from and puts back into. */
bool fn_param_closer_for(LowerFn *fn, const MsCloser *closer, MsTy checked);
/* The helper `fn(move holder)` that closes the resources a holder without a close of its own holds, or MIR_NONE
 * when some part cannot be closed this way; and whether it exists. */
uint32_t lower_close_parts(Lower *cx, MsTy ty);
bool lower_parts_supported(Lower *cx, MsTy ty);
/* The function that closes a part of type `ty` taken out of its holder, or MIR_NONE when it holds no resource. */
uint32_t lower_part_close(Lower *cx, MsTy ty);
/* The function `fn(move value)` that closes an interface value through its `close` operation. */
uint32_t lower_close_iface(Lower *cx, MsTy ty);
/* The function that drops the block of an owned interface value whose payload `receiver` is a resource: it closes the
 * payload and frees the block. MIR_NONE when the type holds no resource. */
uint32_t lower_vtable_close_drop(Lower *cx, MsTy receiver, MirTy data_ty);
/* Whether a temporary of the type `checked` closes where its statement ends, and its owner: the value goes into a
 * slot of the innermost scope, and the result is the view the callee reads. */
bool fn_temp_closes(LowerFn *fn, MsTy checked);
MirValue fn_own_temporary(LowerFn *fn, MsTy checked, MirValue value);
/* A call result a comparison reads: it closes with the statement. */
MirValue fn_closing_operand(LowerFn *fn, const MsExpr *operand, MirValue value);
MirValue fn_pending_own(LowerFn *fn, MsTy checked, MirValue value);
/* The resources the other fields of record `base` hold, closed with the statement once field `moved` has left it; the mask of the fields taken out. */
uint32_t fn_close_rest(LowerFn *fn, const MsExpr *member, MirValue base, uint32_t type_id, uint32_t moved);
MirValue fn_pending_take(LowerFn *fn, MirValue slot, MirTy ty);
/* lower_temp.c: argument `index` of call `expr`, written as `written`, read as `value`: closed with its statement
 * when it is a borrowed temporary. */
MirValue fn_closing_temporary(LowerFn *fn, const MsExpr *expr, uint32_t index, const MsExpr *written, MirValue value);
bool fn_stmt_has_temporary(LowerFn *fn, const MsStmt *stmt);
/* Whether the expression holds a call whose borrowed resource argument closes where the expression ends. */
bool fn_expr_has_temporary(LowerFn *fn, const MsExpr *expr);
/* The base of the field read `member`, closed with its statement when it is a temporary. */
MirValue fn_closing_base(LowerFn *fn, const MsExpr *member, MirValue base);
bool fn_callee_target(LowerFn *fn, const MsCall *call, LowerTarget *out);
const MsExpr *fn_written_arg(const MsExpr *call, MsNode node);
/* Whether a copy no `.clone()` asked for is still allowed (see `fn_implicit_clone`): code that builds closure bodies without a
 * LowerFn asks before it copies. */
bool lower_hidden_copies_allowed(void);
/* The value of a parameter the call leaves to its default (lower_call.c). */
MirValue fn_default_argument(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected, const LowerOuterEnv *outer);
/* Whether a default the call omits uses `?`, which leaves the call (lower_default.c). */
bool fn_call_default_tries(const LowerFn *fn, const MsCall *call);

/* The callee of a call, with explicit type arguments set aside: `value.method[T](args)` calls `value.method`. */
static inline const MsExpr *fn_call_callee(const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_APPLY && callee->u.apply.types.len != 0 && callee->u.apply.left->kind == MS_E_MEMBER
             ? callee->u.apply.left
             : callee;
}
bool fn_shape_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out);
bool fn_value_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirTy first_type_arg,
                          MirValue *out);
enum { LOWER_MAX_ARGS = 64 }; /* the most arguments a call lowers: a record constructor takes one per field */

bool fn_arg_moves(LowerFn *fn, const MsExpr *expr, const MsCall *call, uint32_t index, const MsExpr *written);
/* After the close of a part returned `result`: faults when it is an error, else drops it. */
void lower_close_check(MirBuilder *b, MirValue result);
/* The close thunk of a type an escaping closure owns as a capture, when it has anything to close. */
bool fn_capture_closer(LowerFn *fn, MsTy checked, MirTy ty, uint32_t *silent);
/* Binds `local`, of checker type `checked`, to the fresh owned `value` in a slot its scope closes. */
/* Allocates the slots of the locals that live in memory (resources, and variables a lambda changes). */
void fn_init_closing(LowerFn *fn);
/* The index in the closing tables of the `var` variable (local or parameter) `ref` names that lives in a slot, or UINT32_MAX. */
/* `x = rhs` on a record local that lives in a cell: the cell gives the old record up before `rhs` is lowered, and `rhs`
 * reads it as a value (`fn_cell_old_read`), so a dying receiver is a value the optimizer can move from, as for a variable.
 * `fn_cell_takes_back` drops what `rhs` did not move and stores the new value. */
bool fn_cell_gives_up(LowerFn *fn, const MsRef *ref, MsName name, MsTy checked);
bool fn_cell_old_read(const LowerFn *fn, const MsRef *ref, MsName name, MirValue *value);
void fn_cell_takes_back(LowerFn *fn, const MsRef *ref, MsName name, MirValue value);
uint32_t fn_closing_at(const LowerFn *fn, const MsRef *ref, MsName name);
/* A value an assignment replaced: the innermost scope closes it where it ends. */
bool fn_close_replaced(LowerFn *fn, MsTy checked, MirValue old);

/* The scope no longer drops `value`: its new owner does. */
void fn_disown(LowerFn *fn, MirValue value);

/* Binds the names of `pattern` to the parts of `value` (lower_destructure.c). */
bool fn_bind_parts(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owned, const MirVar *owner,
                   bool reassignable, bool part_owned, MsTy checked_record);
bool fn_bind_closing_in(LowerFn *fn, uint32_t scope, uint32_t local, MsTy checked, MirValue value, bool is_var);
bool fn_bind_closing(LowerFn *fn, uint32_t local, MsTy checked, MirValue value, bool is_var);
/* A read of the `var` resource `ref` names: the slot's current value, or false when it is not one. */
bool fn_closing_read(LowerFn *fn, const MsRef *ref, MsName name, MirValue *view);
/* `name = value` where `name` is a `var` resource: the value it holds is closed, then `value` takes its place. */
bool fn_closing_assign(LowerFn *fn, const MsRef *ref, MsName name, MsTy checked, MirValue value, bool *done);
/* Binds the `move` parameter `index` of checker type `checked`, whose incoming value `value` the function owns, in a
 * slot its scope closes; `var` is the variable the body reads it through. */
bool fn_own_param(LowerFn *fn, uint32_t index, MsTy checked, MirValue value, MirVar var, bool fields_only);
/* A moving read of the closed resource `name` (read as `view`): the slot is given up and its value taken. */
bool fn_closing_take(LowerFn *fn, const MsRef *ref, MirValue view, MirValue *taken);
bool fn_closing_move(LowerFn *fn, const MsExpr *name, MirValue view, MirValue *taken);

/* ---- places (lower_stmt.c) ---- */

/* Whether `place` is an owning `var` local or a member path rooted in one. */
/* Whether `place` is an owning variable (or a path in one): a value a `var` call can change in place. */
bool fn_place_owns(LowerFn *fn, const MsExpr *place);
bool fn_place_changeable(LowerFn *fn, const MsExpr *place);
/* As `fn_place_changeable`, or a member path through the `?` of such a place (`n?.next`): the receiver of `n?.next?.change()`. */
bool fn_try_place_changeable(LowerFn *fn, const MsExpr *place);
/* The owned value of an owning `var` local or a member or element path, for a change that `fn_put_place` stores back. */
bool fn_late_field(LowerFn *fn, const MsExpr *expr, MsRef *out);
bool fn_take_place(LowerFn *fn, const MsExpr *place, MirValue *out);
MirValue fn_missing_value(LowerFn *fn, MsPos at);
bool fn_entry_read_parts(LowerFn *fn, const MsExpr *place, MsExpr **container, MsExpr **key);
bool fn_default_param_place(const LowerFn *fn, const MsExpr *place, uint32_t *at);
/* `m.get(k)` over a resource as an Optional that views the entry; MIR_NONE (nothing emitted) for any other call. */
MirValue fn_map_get_view(LowerFn *fn, const MsExpr *call);
/* Stores the owned `value` (held by no scope) into `place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value);

/* ---- statements, expressions and calls ---- */

bool fn_stmts(LowerFn *fn, MsStmts stmts);
void fn_bench_sink(LowerFn *fn, MirValue value);
MirValue fn_default_result(LowerFn *fn);
/* The 64 bits of a number literal's spelling (decimal, 0x, 0b, 0o; `_` ignored); false when it has more. */
bool fn_number_bits(MsSpan text, uint64_t *out);
/* Whether `expr` is a text with no interpolation, a static string. */
bool fn_is_text_literal(const MsExpr *expr);
MirValue fn_expr(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want);
bool fn_call_never(const LowerFn *fn, const MsExpr *expr);
/* A call of the runtime function `name` (borrowed arguments; a result that needs a drop is fresh). */
MirValue fn_runtime_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret);
/* A new empty map or set of type `ty`: a pure, fresh runtime call, so an unused one is removed. */
MirValue fn_empty_map(LowerFn *fn, MirTy ty);
bool fn_has_raw_pair(LowerFn *fn, MirValue optional, MirValue *out);
bool fn_signature_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out);
MirRole fn_native_role(const MirModule *module, MsSpan name, MirTy first);
uint32_t fn_runtime_extern(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret);
/* A map literal: an empty map the entries are added to through `msrt_map_add`. */
/* A standard operation of the type `owner` as its runtime native; false when the runtime has none by that name. */
bool fn_native_on(LowerFn *fn, const MsExpr *place, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args,
                  MirTy ret, MirValue *out);
/* The same for a receiver that lives at the address `slot` (args[0] is a view of it): a native that changes its receiver
 * writes through the slot. */
bool fn_native_through(LowerFn *fn, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args,
                       MirTy ret, MirValue *out);
/* Whether the native `operation` of `owner` writes its receiver in place. */
bool fn_native_changes_receiver(LowerFn *fn, MsTy owner, MsSpan operation, MirTy ret);

/* lower_native_list.c: natives on lists that edit an element in place or close what they replace. `native_on` is the
 * dispatcher that calls them; `lists_in_place` says whether borrowing a list expression gives it where it lies. */
bool native_on(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc,
               const MirValue *args, MirTy ret, MirValue *out);
bool lists_in_place(LowerFn *fn, const MsExpr *expr);
/* The `sort.cmp` thunk the runtime sort calls for comparator type `closure` over `elem`s; MIR_NONE on failure. */
/* An operand in a slot of its own, for a native that reads or takes it by address; `lookup` only borrows it. */
MirValue fn_operand_slot(LowerFn *fn, const MsExpr *expr, bool lookup);
uint32_t fn_sort_thunk(LowerFn *fn, MirTy elem, MirTy closure);
/* The thunk the runtime `Map.update` calls for a `change` closure over values of type `value`. */
uint32_t fn_update_thunk(LowerFn *fn, MirTy value, MirTy closure);
MirValue fn_list_get(LowerFn *fn, MirValue list, MirValue index, MirTy elem);
bool fn_list_append(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out);
bool fn_list_pop(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirTy ret, MirValue *out);
bool fn_list_swap(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out);
struct MsNativeSig;
void fn_native_precheck(LowerFn *fn, const struct MsNativeSig *sig, MsTy owner, uint32_t argc, const MirValue *args);
bool fn_list_set(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out);
bool fn_list_set_closing(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, uint32_t argc,
                         const MirValue *args, MirValue *out);
bool fn_native_closing_take(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc,
                                const MirValue *args, MirValue *out);
/* `left op right` over two values of one standard type (lower_expr.c). */
MirValue fn_compare_values(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right);
bool fn_record_operator(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right, MirCc cc, MirValue *answer);
MirValue fn_set_from_list(LowerFn *fn, MirValue values, MirTy ty);
MirValue fn_map_literal(LowerFn *fn, const MsExpr *expr);
MirValue fn_map_index(LowerFn *fn, MirValue map, const MsExpr *key, MirTy ty);
MirValue fn_entry_address(LowerFn *fn, MirValue container, const MsExpr *key, MirTy *entry_ty);
void fn_fault_missing_key(LowerFn *fn, MirValue key, MirTy key_ty);
/* `cur = n.next` over a payload view of `cur` (lower_assign_take.c): the new value, or MIR_NONE when not that shape. */
MirValue fn_take_field_of_old(LowerFn *fn, const MsStmt *stmt, MirVar var);
bool fn_take_field_into_slot(LowerFn *fn, const MsStmt *stmt, const MsRef *ref, MsName name, bool *done);
/* `x or d` over a nullable `x` (lower_or.c). */
MirValue fn_lower_or_null(LowerFn *fn, const MsExpr *expr);
MirValue fn_lower_logical(LowerFn *fn, const MsExpr *expr); /* `a && b`, `a || b` */
/* A call recorded with a bodiless standard operation as its callee. */
MirValue fn_native_call(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret);

/* `left op right` on a BigInt through its runtime function; false when the operands are not a value object. */
/* `-value` on a value object or inline native record that has a runtime `negate`. */
bool fn_object_negate(LowerFn *fn, MirValue operand, MirValue *out);
bool fn_object_binary(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right, MirValue *out);

/* A call of the runtime function `name` that returns a Result from a status: the native returns a u8 status and
 * writes the ok payload (and the failure's text) through trailing addresses. False when `name` has no such
 * signature, and nothing was emitted. */
/* The runtime's descriptor operand of kind `kind` (NS_ELEM_DESC...) for the collection among `args`. */
bool fn_descriptor_argument(LowerFn *fn, uint8_t kind, const MirValue *args, uint32_t nargs, MirValue *out);
/* `list.group_by(key)` expanded inline; false when the receiver is not a list or the result not a map of lists. */
bool fn_list_group_by(LowerFn *fn, const MirValue *args, MirTy ret, MirValue *out);
/* A native declared `@op=<name>` as the few MIR instructions it stands for (lower_scalar_ops.c); false, with nothing
 * emitted, when the operands are not the types the operation takes. */
bool fn_inline_scalar_op(LowerFn *fn, const char *name, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out);
bool fn_status_call(LowerFn *fn, MsName name, uint32_t module, const MirValue *args, uint32_t nargs, MirTy ret,
                    MirValue *out);
/* A call of a function the standard library declares without a body: the runtime function `msrt_<name>`. */
/* The shape table of `ty`, with the hooks its types declare built first. */
MirValue fn_shape(LowerFn *fn, MirTy ty);
bool fn_map_from_entries(LowerFn *fn, const MirValue *args, MirTy ret, MirValue *out);
/* The runtime function of `operation` on `owner` called with `args`, or the value itself for a conversion to its own type. */
MirValue fn_native_default(LowerFn *fn, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args, MirTy ret);
MirValue fn_builtin_call(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ret);
/* The runtime function a bodiless standard-library function `id` is, called with `arg_count` arguments. */
MirValue fn_builtin_named(LowerFn *fn, MsSymbolId id, uint32_t arg_count, const MirValue *args, MirTy ret);

/* The expression's value after the conversion the checker recorded on it (an interface view, ...). */
MirValue fn_convert(LowerFn *fn, const MsExpr *expr, MirValue value);
/* The checked type of `expr` as it is read: a local narrowed by `v != null` reads as its payload type. */
MsTy fn_read_type(const LowerFn *fn, const MsExpr *expr);
/* `for x in <list or range>` (lower_for.c) and interpolated text (lower_text.c). */
bool fn_for(LowerFn *fn, const MsStmt *stmt);
MirValue fn_text(LowerFn *fn, const MsExpr *expr);
/* An operation done by the runtime's walker over a type's shape, or MIR_NONE when it has none. */
MirValue fn_value_operation(LowerFn *fn, MsSpan operation, const MirValue *args, uint32_t nargs, MirTy ret);

/* The text of `value` of MIR type `ty` through the type's shape (`msstd_value_text`). */
MirValue fn_value_text(LowerFn *fn, MirValue value, MirTy ty);
MirValue fn_value_repr(LowerFn *fn, MirValue value, MirTy ty);
/* Unary operators, `try`, and the Result of a failable function (lower_result.c). */
MirValue fn_string_concat(LowerFn *fn, MirValue left, MirValue right);
MirValue fn_unary(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_try(LowerFn *fn, const MsExpr *expr, LowerWant want);
/* Returns the error of the failed Result `value` from the function, as `?` does. */
bool fn_return_error(LowerFn *fn, MirValue value);
/* `value` (MIR_NONE for a Void ok) as the function's Result; other functions' values pass through. */
bool fn_end_is_reachable(LowerFn *fn);
MirValue fn_result_wrap(LowerFn *fn, MirValue value);
/* Lambdas and calls of function values (lower_closure.c). */
MirValue fn_lambda(LowerFn *fn, const MsExpr *expr);
/* Marks the locals of `body` that a lambda written in it changes: they live in slots the lambda borrows. */
void fn_find_shared(LowerFn *fn, MsStmts body);

/* The parameters and locals of `fn` that `lambda` reads (lower_captures.c); false when a capture is not lowered yet. */
bool find_captures(LowerFn *fn, const MsExpr *lambda, LowerCapture **out, uint32_t *count);

/* Whether `lambda` changes each of `captures`: `changed` gets one flag per capture. */
bool capture_changes(LowerFn *fn, const MsExpr *lambda, const LowerCapture *captures, uint32_t count, bool *changed);

/* Whether `sym` is a parameter of `lambda` itself rather than something it captures. */
bool is_own_param(const LowerFn *fn, const MsExpr *lambda, MsName sym, const MsRef *ref);
/* Reserves the closure function of function type `fn_ty` with `count` captures (their types in `captures`). */
uint32_t lower_closure_func(Lower *cx, MirTy fn_ty, const LowerCapture *captures, uint32_t count);
/* The position of the interface operation the member `callee` names (`index` when it is not a member). */
uint32_t fn_operation_index(LowerFn *fn, const MsExpr *callee, uint32_t index);
MirValue fn_call_value(LowerFn *fn, const MsExpr *expr, const MsRef *callee);
/* `value` as a function value of type `to`, which differs from its own only in the parameters a call may leave out. */
bool fn_adapt_function_args(LowerFn *fn, uint32_t func, const MsCall *call, MirValue *args);
MirValue fn_adapt_function(LowerFn *fn, MirValue value, MirTy to_ty, MsTy to_checked);

/* A `var` argument: the place's value moved into a slot whose address is passed, and put back after the call. */
typedef struct VarSlot {
  const MsExpr *place;
  MirValue slot;
  MirTy ty;
  MirValue record; /* the record `place` is a field of, taken out of its variable by `fn_take_field`, else MIR_NONE */
  bool in_place; /* `slot` is the address of a list element: nothing goes back */
  MirValue home; /* the address of the list element a `place?` receiver lies in, else MIR_NONE */
  MirTy optional; /* the optional `place` holds when `ty` is the payload a `place?` receiver changed, else MIR_NONE */
  struct VarSlot *outer; /* `a?.b?.change()`: the slot of `a`'s payload, whose field `b` is this slot's home; it goes back after this one */
} VarSlot;
bool fn_list_element_addr(LowerFn *fn, const MsExpr *place, MirValue *addr);
/* A field of a closing local, as its address in the local's slot (lower_field.c). */
bool fn_field_address(LowerFn *fn, const MsExpr *place, MirValue *addr);
/* Assigns `value` to the field at `address` where it lies: the old one is dropped or closed first. */
bool fn_store_field_in_place(LowerFn *fn, const MsExpr *place, MirValue address, MirValue value);
/* Reads the field `expr` names where it lies, when its record stays in a cell. */
bool fn_read_field_in_place(LowerFn *fn, const MsExpr *expr, MirValue *value);
bool fn_place_address(LowerFn *fn, const MsExpr *place, MirValue *addr, MirTy *ty);
MirValue fn_try_var_slot(LowerFn *fn, const MsExpr *expr, VarSlot *out);
/* Evaluates the scalar index keys of `place` now, outermost first, so a later argument cannot run before them. */
void fn_presolve_keys(LowerFn *fn, const MsExpr *place);
MirValue fn_var_slot(LowerFn *fn, const MsExpr *place, VarSlot *out, const VarSlot *earlier, uint32_t nearlier);
bool fn_default_var_slot(const LowerFn *fn, const MsExpr *place, MirValue *slot); /* a default argument passes the callee's own `var` parameter on */
bool fn_var_slots_back(LowerFn *fn, VarSlot *slots, uint32_t count);
MsSymbolId fn_symbol_at(const Lower *cx, MsNodeRef decl);
const MsMethodEntry *fn_method_entry(const Lower *cx, uint32_t module, MsNode node);
MirValue fn_function_value(LowerFn *fn, const MsExpr *expr, const MsRef *ref);
MirValue fn_bound_method(LowerFn *fn, const MsExpr *expr, const MsRef *ref, const MsExpr *typed);
MirValue fn_name_ref(LowerFn *fn, const MsExpr *expr, const MsRef *ref);
const MsCall *fn_find_call(const MsFacts *facts, MsNode node);
/* A parameter name inside a lambda body that is one of its captures: its value in `out`. */
bool fn_lambda_name(LowerFn *fn, const MsExpr *expr, const MsRef *ref, MirValue *out);
/* Lowers the bodies of the lambdas made so far; `*progressed` is set when it lowered any. */
bool lower_lambda_bodies(Lower *cx, bool *progressed);
/* A list literal (lower_list.c). */
MirValue fn_index(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_list(LowerFn *fn, const MsExpr *expr);
/* `if x := value:` (lower_iflet.c): whether the value holds a payload, and binding the payload. */
MirValue fn_iflet_test(LowerFn *fn, MirValue value);
bool fn_iflet_bind(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owns);
bool fn_iflet_owns(LowerFn *fn, const MsStmt *stmt);
/* The payload of the Optional or Result `value`, taken out of it: `value` is released but for the payload. */
MirValue fn_take_payload(LowerFn *fn, MirValue value, MirTy *ty);
/* The value a call's new owner takes from a dying temporary the call answers (`id(make())`, `make().get()`), or MIR_NONE. */
MirValue fn_take_from_temporary(LowerFn *fn, const MsExpr *call, MirValue value);
bool fn_probe_parts(const LowerFn *fn, const MsStmt *stmt, MsExpr **left, MsExpr **index);
bool fn_probe_begin(LowerFn *fn, const MsStmt *stmt, MirValue *cond, MirValue *address, MirTy *ty);
bool fn_lend_writeback(LowerFn *fn, struct VarSlot *lent);
bool fn_probe_bind(LowerFn *fn, const MsStmt *stmt, MirValue address, MirTy ty);
void fn_probe_end(LowerFn *fn, bool falls_out);
void fn_writebacks_put(LowerFn *fn, uint32_t keep);
/* `match` over an alternative (lower_match.c). */
MirValue fn_match(LowerFn *fn, const MsExpr *expr);

/* The value of a variable, and a new one for local `local` of the function. */
MirVar fn_local(LowerFn *fn, uint32_t local, MirTy ty);
bool fn_cond_branch(LowerFn *fn, const MsExpr *cond, MirBlock then, MirBlock otherwise);

/* The MIR type of the checker's type `ty` in this function (its variables replaced). */
static inline MirTy fn_type(LowerFn *fn, MsTy ty) {
  return lower_type(fn->cx, &fn->subst, ty);
}

static inline MirLoc fn_loc(const LowerFn *fn, MsPos pos) {
  return (MirLoc){fn->file, pos.line, pos.column, fn->b.loc.scope}; /* inside a default argument's scope, stays in it */
}

#endif
