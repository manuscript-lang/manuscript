/* Lowering of function bodies (the Rust lowering's func.rs, stmt.rs and expr.rs).
 *
 * Handled so far, exactly the checker's first slice (check_body.c) minus what needs ownership:
 * functions whose parameters, locals and result are `Int`, `Float` or `Bool`, with `String` only
 * as a parameter, a literal or a concatenation that is returned; `name := value`, `var name =
 * value`, `return`, literals, names, `not`, unary `-` and `+`, and the binary operators.
 * A function with anything else is skipped: `lb_function` returns false and adds nothing. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"
#include "ms/lower.h"
#include "ms/lower_internal.h"
#include "ms/lower_scope.h"
#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"
#include "ms/ty_algebra.h"

LbVal lb_unsupported(Lb *lb) {
    lb->ok = false;
    return LB_FAIL;
}

static MsTy lb_primitive(const MsCheck *c, const char *name) {
    const MsSymId sym = ms_map_get(&c->primitives, ms_intern_cstr(c->names, name));
    return sym == MS_NONE ? MS_TY_NONE : c->syms.ty[sym];
}

/* `ty` as the function being lowered sees it: the variables of the instance are the types they
 * stand for, through arguments, parameters and results (`List[T]` becomes `List[Int]`). A variable
 * is matched by id, as the checker's substitution does. */
static MsTy lb_ty(Lb *lb, MsTy ty) {
    if (lb->nsub == 0 || ty == MS_TY_NONE) {
        return ty;
    }
    MsArena scratch = {0};
    if (ms_ty_kind(&lb->c->tys, ty) != MS_K_VARIABLE && !ms_ty_has_variable(&lb->c->tys, &scratch, ty)) {
        ms_arena_free(&scratch);
        return ty;
    }
    const MsTySubst subst = {lb->sub_vars, lb->sub_args, lb->nsub};
    const MsTy result = ms_ty_subst(&lb->mut->tys, &scratch, ty, &subst);
    ms_arena_free(&scratch);
    return result;
}

/* A record, Optional or Result type. */
static MirTy lb_mir_alt(Lb *lb, MsTy ty) {
    if (ms_classify(lb->classifier, ty) == MS_CLASS_RESOURCE) {
        return MIR_NONE; // its close is not recorded yet
    }
    const MirTy record = lr_type(lb, ty);
    if (record != MIR_NONE) {
        return record;
    }
    const MirTy user_enum = le_type(lb, ty);
    return user_enum != MIR_NONE ? user_enum : la_type(lb, ty);
}

/* The MIR type of a checker type this pass handles, or MIR_NONE. */
MirTy lb_mir_ty(Lb *lb, MsTy ty) {
    ty = lb_ty(lb, ty);
    if (ms_ty_kind(&lb->c->tys, ty) == MS_K_FUNCTION) {
        return lb_fn_ty(lb, ty);
    }
    if (ty == lb->int_ty) {
        return MIR_INT;
    }
    if (ty == lb->float_ty) {
        return MIR_FLOAT;
    }
    if (ty == lb->bool_ty) {
        return MIR_BOOL;
    }
    if (ty == lb->string_ty) {
        return MIR_STR;
    }
    const MirTy list = lst_type(lb, ty);
    return list != MIR_NONE ? list : lb_mir_alt(lb, ty);
}

MirLoc lb_loc(const Lb *lb, MsPos pos) {
    return (MirLoc){.file = 0, .line = pos.line, .col = pos.column, .scope = lb->b.loc.scope};
}

void lb_emit_plain(Lb *lb, MirOp op) {
    (void)mir_b_emit(&lb->b, op, NULL, 0, (MirImm){0}, MIR_NONE);
}

/* `depth.enter` and `depth.leave` bracket a function; a closure body has neither. */
static void lb_depth(Lb *lb, MirOp op) {
    if (!lb->closure) {
        lb_emit_plain(lb, op);
    }
}

/* Releases an owned temporary once its last use is past. */
void lb_drop(Lb *lb, MirValue v) {
    const MirLoc loc = lb->b.loc;
    if (lb_is_fn(lb, mir_b_ty(&lb->b, v))) {
        lb->b.loc = MIR_LOC_NONE; // the text form prints no position on a closure's release
    }
    (void)mir_b_emit(&lb->b, MOP_Drop, &v, 1, (MirImm){0}, MIR_NONE);
    lb->b.loc = loc;
}

/* Whether a value of `ty` owns something its holder must release: a String, a function value or a
 * record holding a String. */
bool lb_owns(Lb *lb, MirTy ty) {
    return ty != MIR_NONE && (ty == MIR_STR || lb_is_fn(lb, ty) || mir_needs_drop(lb->m, ty));
}

/* An owned temporary of the statement: dropped where the statement ends, newest first. Where no such
 * end exists (inside a condition, an arm or the right side of `and`/`or`) it is dropped now. */
void lb_hold_temp(Lb *lb, MirValue v) {
    const bool simple = lb->stmt != NULL && lb->branching == 0 &&
                        (lb->stmt->kind == MS_S_BIND || lb->stmt->kind == MS_S_RETURN ||
                         lb->stmt->kind == MS_S_ASSIGN || lb->stmt->kind == MS_S_CALL);
    if (!simple) {
        lb_drop(lb, v);
        return;
    }
    MIR_PUSH(lb->m, lb->temps, lb->ntemps, lb->ctemps, MirValue, v);
}

/* Drops the statement's temporaries from `mark` on, newest first. */
static void lb_release_temps(Lb *lb, uint32_t mark) {
    while (lb->ntemps > mark) {
        lb_drop(lb, lb->temps[--lb->ntemps]);
    }
}

/* A `return` leaves with the temporaries still held: its scope exit drops them. */
static void lb_own_temps(Lb *lb, uint32_t mark) {
    for (uint32_t i = mark; i < lb->ntemps; i++) {
        lscope_own(&lb->scopes, lb->temps[i], 0);
    }
    lb->ntemps = mark;
}

/* Copies a borrowed String into a value the caller owns. */
static MirValue lb_copy(Lb *lb, MirValue v) {
    const MirImm one = {.tag = MI_INT, .i = 1};
    return mir_b_emit(&lb->b, MOP_Clone, &v, 1, one, mir_b_ty(&lb->b, v));
}

/* ---- literals ---- */

static LbVal lb_number(Lb *lb, const MsExpr *e, bool negate) {
    const MsStr text = ms_number_canonical(&lb->m->arena, ms_name(lb->c->names, e->u.sym));
    char *digits = ms_arena_strndup(&lb->m->arena, text.ptr, text.len);
    if (lb_ty(lb, lb->facts->expr_ty[e->id]) == lb->float_ty) {
        const double value = strtod(digits, NULL);
        MirImm imm = {.tag = MI_FLOAT};
        const double signed_value = negate ? -value : value;
        memcpy(&imm.i, &signed_value, sizeof signed_value);
        return (LbVal){mir_b_emit(&lb->b, MOP_FConst, NULL, 0, imm, MIR_FLOAT), false};
    }
    const int64_t value = (int64_t)strtoull(digits, NULL, 10);
    return (LbVal){mir_b_iconst(&lb->b, negate ? -value : value), false};
}

/* A literal with no interpolation. */
static LbVal lb_text(Lb *lb, const MsExpr *e) {
    if (e->u.text.len > 1) {
        return lt_text(lb, e); // an interpolation joins its pieces
    }
    if (e->u.text.len != 1 || e->u.text.ptr[0].expr != NULL) {
        return lb_unsupported(lb);
    }
    const MsStr lit = e->u.text.ptr[0].lit;
    MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
    return (LbVal){mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false};
}

/* ---- names ---- */

/* A `var` parameter arrives as a pointer to the caller's variable. The body works on a copy held
 * in an SSA variable: it is loaded on entry and stored back before every return (`noalias` says
 * nothing else touches the memory meanwhile). */
static MirValue lb_load(Lb *lb, MirValue slot, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
}

static void lb_store(Lb *lb, MirValue slot, MirValue value) {
    const MirValue args[2] = {slot, value};
    (void)mir_b_emit(&lb->b, MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
}

static LbVal lb_name(Lb *lb, const MsExpr *e) {
    const MsFacts *facts = lb->facts;
    if (facts->res_kind[e->id] == MS_RES_SYMBOL) {
        return lb_function_value(lb, e);
    }
    if (facts->res_kind[e->id] == MS_RES_CASE) {
        return la_nullary(lb, e);
    }
    if (facts->res_kind[e->id] != MS_RES_BINDING) {
        return facts->res_kind[e->id] == MS_RES_NONE ? la_none(lb, e) : lb_unsupported(lb);
    }
    const uint32_t binding = facts->res_ref[e->id];
    if (lb->var_of[binding] != MIR_NONE) {
        return (LbVal){mir_b_use_var(&lb->b, lb->var_of[binding]), false};
    }
    return (LbVal){lb->value_of[binding], false};
}

/* ---- operators ---- */

static LbVal lb_match(Lb *lb, const MsExpr *e);
static void lb_name_value(Lb *lb, MirValue value, MsSym name, bool param);

static LbVal lb_unary(Lb *lb, const MsExpr *e) {
    const MsExpr *operand = e->u.bin.left;
    const MsUnaryOp op = (MsUnaryOp)e->op;
    if (op == MS_U_TRY) {
        return la_try(lb, e);
    }
    if (op == MS_U_NEG && operand->kind == MS_E_NUMBER) {
        return lb_number(lb, operand, true);
    }
    const LbVal x = lb_expr(lb, operand);
    if (!lb->ok || op == MS_U_PLUS) {
        return x;
    }
    const MirTy ty = mir_b_ty(&lb->b, x.v);
    MirOp mir_op = MOP_Not;
    if (op != MS_U_NOT) {
        mir_op = ty == MIR_FLOAT ? MOP_FNeg : MOP_INegChk;
    }
    return (LbVal){mir_b_emit(&lb->b, mir_op, &x.v, 1, (MirImm){0}, ty), false};
}

/* `left and right` and `left or right`: the right side runs only when the left does not decide. */
static LbVal lb_short_circuit(Lb *lb, const MsExpr *e) {
    const bool is_or = e->op == MS_B_OR;
    const LbVal left = lb_expr(lb, e->u.bin.left);
    if (!lb->ok) {
        return left;
    }
    const MirBlock rhs = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    const MirValue result = mir_b_add_block_param(&lb->b, join, MIR_BOOL, MM_BORROW);
    const MirValue decided = mir_b_bconst(&lb->b, is_or);
    if (is_or) {
        mir_b_br_if(&lb->b, left.v, join, &decided, 1, rhs, NULL, 0);
    } else {
        mir_b_br_if(&lb->b, left.v, rhs, NULL, 0, join, &decided, 1);
    }
    mir_b_seal_block(&lb->b, rhs);
    mir_b_switch_to(&lb->b, rhs);
    lb->branching++;
    const LbVal right = lb_expr(lb, e->u.bin.right);
    lb->branching--;
    if (!lb->ok) {
        return right;
    }
    mir_b_br(&lb->b, join, &right.v, 1);
    mir_b_seal_block(&lb->b, join);
    mir_b_switch_to(&lb->b, join);
    return (LbVal){result, false};
}

static MirOp lb_arithmetic_op(MsBinaryOp op, MirTy ty) {
    const bool is_float = ty == MIR_FLOAT;
    switch (op) {
    case MS_B_ADD: return is_float ? MOP_FAdd : MOP_IAddChk;
    case MS_B_SUB: return is_float ? MOP_FSub : MOP_ISubChk;
    case MS_B_MUL: return is_float ? MOP_FMul : MOP_IMulChk;
    case MS_B_DIV: return is_float ? MOP_FDiv : MOP_SDivChk;
    case MS_B_REM: return MOP_SRemChk;
    case MS_B_OR:
    case MS_B_AND:
    case MS_B_EQ:
    case MS_B_NE:
    case MS_B_LT:
    case MS_B_GT:
    case MS_B_LE:
    case MS_B_GE: break;
    }
    return MOP_COUNT;
}

static MirCc lb_cc(MsBinaryOp op) {
    switch (op) {
    case MS_B_EQ:
    case MS_B_NE: return MCC_EQ;
    case MS_B_LT: return MCC_LT;
    case MS_B_GT: return MCC_GT;
    case MS_B_LE: return MCC_LE;
    case MS_B_GE: return MCC_GE;
    case MS_B_OR:
    case MS_B_AND:
    case MS_B_ADD:
    case MS_B_SUB:
    case MS_B_MUL:
    case MS_B_DIV:
    case MS_B_REM: break;
    }
    return MCC_EQ;
}

/* The runtime function that joins two strings, declared on first use. */
static uint32_t lb_string_concat(Lb *lb) {
    const MsSym name = mir_name(lb->m, "msrt_string_concat", strlen("msrt_string_concat"));
    const uint32_t found = mir_extern_by_name(lb->m, name);
    if (found != MIR_NONE) {
        return found;
    }
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, 2);
    params[0] = params[1] = (MirParam){MIR_STR, MM_BORROW};
    const MirExtern ext = {
        .name = name, .params = params, .nparams = 2, .ret = MIR_STR, .fresh = true, .leaf = true,
        .role = MR_STRING_CONCAT};
    return mir_add_extern(lb->m, &ext);
}

static LbVal lb_concat(Lb *lb, LbVal left, LbVal right) {
    const MirValue args[2] = {left.v, right.v};
    const MirValue joined = mir_b_call_rt(&lb->b, lb_string_concat(lb), args, 2);
    for (uint32_t i = 0; i < 2; i++) {
        if ((i == 0 ? left : right).owned) {
            lb_drop(lb, args[i]); // an owned operand is a temporary: the join only borrowed it
        }
    }
    return (LbVal){joined, true};
}

static LbVal lb_compare(Lb *lb, MsBinaryOp op, LbVal left, LbVal right) {
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    const MirImm cc = {.tag = MI_CC, .a = (uint32_t)lb_cc(op)};
    const MirValue args[2] = {left.v, right.v};
    if (lb_owns(lb, ty)) {
        return lb_unsupported(lb);
    }
    const MirOp mir_op = ty == MIR_FLOAT ? MOP_FCmp : MOP_ICmp;
    MirValue result = mir_b_emit(&lb->b, mir_op, args, 2, cc, MIR_BOOL);
    if (op == MS_B_NE) {
        result = mir_b_emit(&lb->b, MOP_Not, &result, 1, (MirImm){0}, MIR_BOOL);
    }
    return (LbVal){result, false};
}

/* `left op right` on lowered operands (not `and` and `or`, which short-circuit). */
static LbVal lb_apply(Lb *lb, MsBinaryOp op, LbVal left, LbVal right) {
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    if (op == MS_B_ADD && ty == MIR_STR) {
        return lb_concat(lb, left, right);
    }
    if (lb_owns(lb, ty)) {
        return lb_unsupported(lb);
    }
    const MirOp arithmetic = lb_arithmetic_op(op, ty);
    if (arithmetic == MOP_COUNT) {
        return lb_compare(lb, op, left, right);
    }
    return (LbVal){mir_b_binop(&lb->b, arithmetic, left.v, right.v), false};
}

static LbVal lb_binary(Lb *lb, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    if (op == MS_B_AND || op == MS_B_OR) {
        return lb_short_circuit(lb, e);
    }
    if (op == MS_B_ADD && lb->facts->expr_ty[e->id] == lb->string_ty) {
        return lt_text(lb, e); // a chain of string sums is one join
    }
    const LbVal left = lb_expr(lb, e->u.bin.left);
    const LbVal right = lb->ok ? lb_expr(lb, e->u.bin.right) : LB_FAIL;
    if (!lb->ok) {
        return LB_FAIL;
    }
    return lb_apply(lb, op, left, right);
}

/* A call of a module function the checker resolved; MIR_NONE-valued `func_of` means the callee
 * is not lowered, so neither is the caller. */
/* A `var` argument: the caller's own `var` local or `var` parameter, passed by address. It lives
 * in an SSA variable, so it goes through a fresh slot that the call may change and is read back
 * into the variable afterwards (`*written` is that slot). */
static MirValue lb_var_argument(Lb *lb, const MsExpr *arg, uint32_t *binding_out, MirValue *written) {
    *written = MIR_NONE;
    if (arg->kind != MS_E_NAME || lb->facts->res_kind[arg->id] != MS_RES_BINDING) {
        lb->ok = false;
        return MIR_NONE;
    }
    const uint32_t binding = lb->facts->res_ref[arg->id];
    *binding_out = binding;
    if (lb->var_of[binding] == MIR_NONE) {
        lb->ok = false;
        return MIR_NONE;
    }
    const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[binding]);
    const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
    lb_store(lb, slot, mir_b_use_var(&lb->b, lb->var_of[binding]));
    *written = slot;
    return slot;
}

/* Whether parameter `index` of the function declared by `d` is handed over: declared `move`, or
 * moved by the body (the ownership pass's `param_consumed`). */
static bool lb_param_moves(const Lb *lb, const MsDecl *d, uint32_t index) {
    return d->u.fn.params.ptr[index]->moving || ((lb->facts->param_consumed[d->id] >> index) & 1u) != 0;
}

/* Whether `e` names a `let` local or a `move` parameter: a String the function owns, so using it
 * as a result or a `move` argument hands it over. */
static bool lb_names_owned(const Lb *lb, const MsExpr *e) {
    const MsFacts *facts = lb->facts;
    if (e->kind != MS_E_NAME || facts->res_kind[e->id] != MS_RES_BINDING) {
        return false;
    }
    const uint32_t binding = facts->res_ref[e->id];
    if (facts->bindings.role[binding] == MS_ROLE_LET) {
        return true;
    }
    const MsFunc *fn = &lb->decl->u.fn;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (lb->binding_at[fn->params.ptr[i]->id] == binding) {
            return lb_param_moves(lb, lb->decl, i);
        }
    }
    return false;
}

/* A call of a module function the checker resolved; a callee that is not lowered (no `func_of`)
 * fails the caller with it. */
/* A `move` argument: an owned temporary is handed over as it is, an owned name moves out of its
 * scope, and anything else is copied. */
MirValue lb_move_argument(Lb *lb, const MsExpr *e) {
    const LbVal value = lb_expr(lb, e);
    if (!lb->ok || value.owned) {
        return value.v;
    }
    if (lb_names_owned(lb, e)) {
        lscope_disown(&lb->scopes, value.v);
        return value.v;
    }
    return lb_copy(lb, value.v);
}

static uint32_t lb_instance(Lb *lb, MsSymId sym, const MsTy *args, uint32_t nargs);

/* The module function a call reaches: the callee's own, or for a generic callee its copy for the
 * type arguments the checker inferred at this call, seen through the instance being lowered. */
static uint32_t lb_callee_func(Lb *lb, const MsExpr *e, MsSymId callee) {
    if (callee == MS_NONE) {
        return MIR_NONE;
    }
    if (lb->c->syms.nvars[callee] == 0) {
        return lb->func_of[callee];
    }
    const MsFacts *facts = lb->facts;
    const uint32_t nargs = facts->call_type_args_len[e->id];
    if (nargs == 0 || nargs != lb->c->syms.nvars[callee] || nargs > LB_MAX_TARGS) {
        return MIR_NONE;
    }
    MsTy args[LB_MAX_TARGS];
    for (uint32_t i = 0; i < nargs; i++) {
        args[i] = lb_ty(lb, facts->type_args[facts->call_type_args_at[e->id] + i]);
    }
    return lb_instance(lb, callee, args, nargs);
}

static LbVal lb_call(Lb *lb, const MsExpr *e) {
    const uint32_t callee = lb->facts->call_callee[e->id];
    if (callee == MS_NONE && lb->facts->res_kind[e->u.call.callee->id] == MS_RES_CASE) {
        return la_case(lb, e);
    }
    if (callee == MS_NONE && lb->facts->call_method[e->id] != MS_NONE) {
        return lst_method(lb, e);
    }
    if (callee == MS_NONE) {
        return lb_call_value(lb, e);
    }
    if (lb->c->syms.kind[callee] == MS_SYM_TYPE) {
        return lr_construct(lb, e);
    }
    const uint32_t func = lb_callee_func(lb, e, callee);
    const uint32_t count = e->u.call.args.len;
    if (func == MIR_NONE || count != lb->c->tys.nparams[lb->c->syms.ty[callee]]) {
        return lb_unsupported(lb);
    }
    const MsTyParam *params = ms_ty_params(&lb->c->tys, lb->c->syms.ty[callee]);
    MirValue *args = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    MirValue *temps = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1); // owned arguments
    uint32_t ntemps = 0;
    MirValue *slots = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    uint32_t *bindings = MS_NEW_N(&lb->b.scratch, uint32_t, (size_t)count + 1);
    // Values first, then the slots of the `var` arguments, in argument order each.
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        slots[i] = MIR_NONE;
        if ((params[i].flags & MS_PARAM_MOVE) != 0 || (i < lb->m->funcs[func].nparams && lb->m->funcs[func].params[i].mode == MM_MOVE)) {
            args[i] = lb_move_argument(lb, e->u.call.args.ptr[i].value);
        } else if ((params[i].flags & MS_PARAM_VAR) == 0) {
            const LbVal value = lb_expr(lb, e->u.call.args.ptr[i].value);
            args[i] = value.v;
            if (value.owned) {
                temps[ntemps++] = value.v; // dropped where the statement ends
            }
        }
    }
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        if ((params[i].flags & MS_PARAM_VAR) != 0) {
            args[i] = lb_var_argument(lb, e->u.call.args.ptr[i].value, &bindings[i], &slots[i]);
        }
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    MirValue result = mir_b_call(&lb->b, func, args, count);
    const uint8_t how = lb->m->funcs[func].ret_borrowed ? lb->facts->call_owned_borrow[e->id] : MS_OWNED_NONE;
    bool owns_result = false;
    if (how != MS_OWNED_NONE) {
        // A borrowing callee over a temporary: the caller owns the result, which is the temporary itself
        // when it came back whole and a copy taken before the temporary is dropped otherwise.
        const uint32_t whole = lb->facts->call_owned_param[e->id];
        const bool is_whole = how == MS_OWNED_WHOLE && whole < count;
        if (is_whole) {
            result = args[whole];
            for (uint32_t i = 0; i < ntemps; i++) {
                temps[i] = temps[i] == result ? MIR_NONE : temps[i];
            }
        } else {
            result = lb_copy(lb, result);
        }
        owns_result = true;
    }
    for (uint32_t i = 0; i < ntemps; i++) {
        if (temps[i] != MIR_NONE) {
            lb_hold_temp(lb, temps[i]);
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        if (slots[i] != MIR_NONE) {
            const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[bindings[i]]);
            mir_b_def_var(&lb->b, lb->var_of[bindings[i]], lb_load(lb, slots[i], ty));
        }
    }
    const bool borrowed = lb->m->funcs[func].ret_borrowed; // a reference into the arguments
    const MirTy result_ty = mir_b_ty(&lb->b, result);
    return (LbVal){result, owns_result || (lb_owns(lb, result_ty) && !borrowed)}; // else a String result is the caller's
}

static LbVal lb_expr_plain(Lb *lb, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: return lb_number(lb, e, false);
    case MS_E_BOOL: return (LbVal){mir_b_bconst(&lb->b, e->u.flag), false};
    case MS_E_TEXT: return lb_text(lb, e);
    case MS_E_NAME: return lb_name(lb, e);
    case MS_E_LAMBDA: return lb_lambda(lb, e);
    case MS_E_UNARY: return lb_unary(lb, e);
    case MS_E_BINARY: return lb_binary(lb, e);
    case MS_E_MATCH: return lb_match(lb, e);
    case MS_E_CALL: return lb_call(lb, e);
    case MS_E_MEMBER: return lr_field(lb, e);
    case MS_E_INDEX:
    case MS_E_APPLY: return lst_index(lb, e);
    case MS_E_LIST: return lst_literal(lb, e);
    case MS_E_VOID:
    case MS_E_PROBE:
    case MS_E_MAP: break;
    }
    return lb_unsupported(lb);
}

/* `e`, wrapped in `some` where the checker found a payload used for an Optional. */
LbVal lb_expr(Lb *lb, const MsExpr *e) {
    const LbVal value = lb_expr_plain(lb, e);
    if (!lb->ok || !lb->facts->some_wrap[e->id]) {
        return value;
    }
    const MirTy payload = mir_b_ty(&lb->b, value.v);
    const bool owns = lb_owns(lb, payload);
    if (value.owned != owns) {
        return lb_unsupported(lb); // a borrowed payload stays a view, an owned one is wrapped (the ownership pass decides which)
    }
    const MirTy ty = mir_ty_opt(lb->m, payload);
    return (LbVal){mir_b_emit(&lb->b, MOP_OptSome, &value.v, 1, (MirImm){0}, ty), owns};
}

/* ---- match ---- */

static bool lb_is_wildcard(const Lb *lb, const MsExpr *path) {
    if (path->kind != MS_E_NAME) {
        return false;
    }
    const MsStr name = ms_name(lb->c->names, path->u.sym);
    return name.len == 1 && name.ptr[0] == '_';
}

/* The value of an integer literal arm: a number, or a negated one. */
static int64_t lb_literal_arm(Lb *lb, const MsExpr *path) {
    const bool negated = path->kind == MS_E_UNARY;
    const MsExpr *number = negated ? path->u.bin.left : path;
    const MsStr text = ms_number_canonical(&lb->m->arena, ms_name(lb->c->names, number->u.sym));
    char *digits = ms_arena_strndup(&lb->m->arena, text.ptr, text.len);
    const int64_t value = (int64_t)strtoull(digits, NULL, 10);
    return negated ? -value : value;
}

/* Where each arm's block is, and the block the arms not named go to. */
typedef struct LbArms {
    MirBlock *blocks;
    MirBlock join;
    MirBlock fallback;
    int64_t wildcard; /* arm index of `_`, or -1 */
} LbArms;

static LbArms lb_open_arms(Lb *lb, const MsExpr *e) {
    const uint32_t count = e->u.match.arms.len;
    LbArms arms = {.blocks = MS_NEW_N(&lb->m->arena, MirBlock, count), .wildcard = -1};
    for (uint32_t i = 0; i < count; i++) {
        arms.blocks[i] = mir_b_new_block(&lb->b);
        if (lb_is_wildcard(lb, e->u.match.arms.ptr[i]->path)) {
            arms.wildcard = i;
        }
    }
    arms.join = mir_b_new_block(&lb->b);
    arms.fallback = arms.wildcard >= 0 ? arms.blocks[arms.wildcard] : mir_b_new_block(&lb->b);
    return arms;
}

/* Branches on the scrutinee once: a `switch` over the literal arms of an Int, a `br_if` over a Bool. */
static void lb_dispatch(Lb *lb, const MsExpr *e, MirValue scrutinee, const LbArms *arms) {
    const MsArm *const *list = (const MsArm *const *)e->u.match.arms.ptr;
    const uint32_t count = e->u.match.arms.len;
    if (mir_ty_data(lb->m, mir_b_ty(&lb->b, scrutinee))->kind == MK_ALT) {
        const MirValue tag = mir_b_emit(&lb->b, MOP_AltTag, &scrutinee, 1, (MirImm){0}, MIR_INT);
        MirCase *cases = MS_NEW_N(&lb->m->arena, MirCase, count);
        uint32_t ncases = 0;
        for (uint32_t i = 0; i < count; i++) {
            if ((int64_t)i != arms->wildcard) {
                cases[ncases++] = (MirCase){lb->facts->arm_case[list[i]->id], {arms->blocks[i], NULL, 0}};
            }
        }
        mir_b_switch(&lb->b, tag, cases, ncases, arms->fallback);
        return;
    }
    if (mir_b_ty(&lb->b, scrutinee) == MIR_INT) {
        MirCase *cases = MS_NEW_N(&lb->m->arena, MirCase, count);
        uint32_t ncases = 0;
        for (uint32_t i = 0; i < count; i++) {
            if ((int64_t)i != arms->wildcard) {
                cases[ncases++] = (MirCase){lb_literal_arm(lb, list[i]->path), {arms->blocks[i], NULL, 0}};
            }
        }
        mir_b_switch(&lb->b, scrutinee, cases, ncases, arms->fallback);
        return;
    }
    MirBlock when_true = arms->fallback, when_false = arms->fallback;
    for (uint32_t i = 0; i < count; i++) {
        if (list[i]->path->kind == MS_E_BOOL) {
            (list[i]->path->u.flag ? &when_true : &when_false)[0] = arms->blocks[i];
        }
    }
    mir_b_br_if(&lb->b, scrutinee, when_true, NULL, 0, when_false, NULL, 0);
}

/* Binds the names an arm gives to the payload of its case: each is the matching field of the
 * scrutinee, read with `alt.get`. The checker bound them to this arm's node. */
static void lb_bind_arm(Lb *lb, const MsArm *arm, MirValue subject) {
    const MirTyData *data = mir_ty_data(lb->m, mir_b_ty(&lb->b, subject));
    const uint32_t index = lb->facts->arm_case[arm->id];
    const MsBindings *bindings = &lb->facts->bindings;
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        for (uint32_t binding = 0; binding < bindings->count; binding++) {
            if (bindings->decl_node[binding] != arm->id || bindings->name[binding] != arm->bindings.ptr[slot].name) {
                continue;
            }
            const MirImm field = {.tag = MI_ALTFIELD, .a = data->id, .b = index, .c = slot};
            const MirTy ty = lb->m->alts[data->id].cases[index].fields[slot].ty;
            lb->value_of[binding] = mir_b_emit(&lb->b, MOP_AltGet, &subject, 1, field, ty);
            lb_name_value(lb, lb->value_of[binding], arm->bindings.ptr[slot].name, false);
        }
    }
}

/* `match` over literal arms with one value each. A Bool match is also how `if c: a else: b` is
 * written. Every arm's value joins in one block parameter. */
static LbVal lb_match(Lb *lb, const MsExpr *e) {
    const MirTy result_ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const LbVal scrutinee = lb_expr(lb, e->u.match.scrutinee);
    const MirTy scrutinee_ty = lb->ok ? mir_b_ty(&lb->b, scrutinee.v) : MIR_NONE;
    const MirTyKind scrutinee_kind = lb->ok ? mir_ty_data(lb->m, scrutinee_ty)->kind : MK_INT;
    const bool aggregate = lb->ok && scrutinee_kind >= MK_TYPE && scrutinee_kind != MK_ALT; // a record: not matched
    if (!lb->ok || result_ty == MIR_NONE || lb_owns(lb, result_ty) || scrutinee_ty == MIR_STR || aggregate ||
        lb_is_fn(lb, result_ty)) {
        return lb_unsupported(lb); // a String result or scrutinee is owned: ownership comes later
    }
    const LbArms arms = lb_open_arms(lb, e);
    const MirValue result = mir_b_add_block_param(&lb->b, arms.join, result_ty, MM_BORROW);
    lb_dispatch(lb, e, scrutinee.v, &arms);
    if (arms.wildcard < 0) {
        mir_b_seal_block(&lb->b, arms.fallback);
        mir_b_switch_to(&lb->b, arms.fallback);
        mir_b_unreachable(&lb->b);
    }
    for (uint32_t i = 0; i < e->u.match.arms.len && lb->ok; i++) {
        mir_b_seal_block(&lb->b, arms.blocks[i]);
        mir_b_switch_to(&lb->b, arms.blocks[i]);
        if (scrutinee_kind == MK_ALT) {
            lb_bind_arm(lb, e->u.match.arms.ptr[i], scrutinee.v);
        }
        lb->branching++;
        const LbVal value = lb_expr(lb, e->u.match.arms.ptr[i]->value);
        lb->branching--;
        if (lb->ok) {
            mir_b_br(&lb->b, arms.join, &value.v, 1);
        }
    }
    mir_b_seal_block(&lb->b, arms.join);
    mir_b_switch_to(&lb->b, arms.join);
    return (LbVal){result, false};
}

/* ---- statements ---- */

/* Names `value` for a debugger, as the Rust lowering does: parameters and single-definition locals. */
static void lb_name_value(Lb *lb, MirValue value, MsSym name, bool param) {
    const MsStr text = ms_name(lb->c->names, name);
    const MirNamedValue named = {value, mir_name(lb->m, text.ptr, text.len), param, 0};
    MIR_PUSH(lb->m, lb->b.f.names, lb->b.f.nnames, lb->b.f.cnames, MirNamedValue, named);
}

static void lb_bind(Lb *lb, const MsStmt *s) {
    const MsPattern *pattern = s->u.bind.pattern;
    const uint32_t binding = lb->facts->pattern_binding[pattern->id];
    const MsTy ty = lb_ty(lb, lb->facts->bindings.ty[binding]);
    LbVal value = lb_expr(lb, s->u.bind.value);
    if (!lb->ok) {
        return;
    }
    if (lb_is_fn(lb, lb_mir_ty(lb, ty)) && (!value.owned || s->u.bind.is_mutable)) {
        lb->ok = false; // a function value is owned by the one local made from a lambda or a name
        return;
    }
    if (lb_is_fn(lb, lb_mir_ty(lb, ty))) {
        lscope_own(&lb->scopes, value.v, 0); // the closure is dropped where its scope ends
    }
    const MirTy bound_ty = lb_mir_ty(lb, ty);
    if (bound_ty != MIR_STR && !lb_is_fn(lb, bound_ty) && lb_owns(lb, bound_ty)) {
        if (!value.owned || s->u.bind.is_mutable) {
            lb->ok = false; // a record local is made from a call or a construction, and is not a `var` yet
            return;
        }
        lscope_own(&lb->scopes, value.v, 0);
    }
    if (ty == lb->string_ty) {
        if (!value.owned) {
            value = (LbVal){lb_copy(lb, value.v), true}; // a borrowed String is copied into the local
        }
        if (!s->u.bind.is_mutable) {
            lscope_own(&lb->scopes, value.v, 0);
        }
    }
    if (s->u.bind.is_mutable) {
        const bool owned = lb_owns(lb, lb_mir_ty(lb, ty));
        lb->var_of[binding] = mir_b_declare_var(&lb->b, lb_mir_ty(lb, ty), owned ? MM_MOVE : MM_BORROW);
        mir_b_def_var(&lb->b, lb->var_of[binding], value.v);
        if (owned) { // owned at each exit of its scope with the value it holds there
            const LbVarOwner owner = {binding, lb->scopes.depth - 1};
            MIR_PUSH(lb->m, lb->vars, lb->nvars, lb->cvars, LbVarOwner, owner);
        }
    } else {
        lb->value_of[binding] = value.v;
        if (pattern->kind == MS_P_NAME) {
            lb_name_value(lb, value.v, pattern->u.name, false);
        }
    }
}

/* Stores each `var` parameter's current value through its pointer, before the function returns. */
void lb_write_back(Lb *lb) {
    if (lb->closure) {
        return; // a closure has no `var` parameters of its own
    }
    const MsFunc *fn = &lb->decl->u.fn;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->is_mutable) {
            const uint32_t binding = lb->binding_at[fn->params.ptr[i]->id];
            lb_store(lb, lb->value_of[binding], mir_b_use_var(&lb->b, lb->var_of[binding]));
        }
    }
}

/* Hands the current value of every owned `var` String declared at `depth` or deeper to its scope,
 * before an exit leaves them. `except` is a value that leaves with the exit and is not dropped. */
void lb_own_vars(Lb *lb, uint32_t depth, MirValue except) {
    for (uint32_t i = lb->nvars; i > 0; i--) {
        const LbVarOwner *owner = &lb->vars[i - 1];
        if (owner->depth < depth) {
            continue;
        }
        const MirValue current = mir_b_use_var(&lb->b, lb->var_of[owner->binding]);
        if (current != except) {
            lscope_own_in(&lb->scopes, owner->depth, current, 0);
        }
    }
}

static bool lb_var_owned(const Lb *lb, uint32_t binding) {
    for (uint32_t i = 0; i < lb->nvars; i++) {
        if (lb->vars[i].binding == binding) {
            return true;
        }
    }
    return false;
}

/* Whether `e` names an owned `var` String. */
static bool lb_names_var(const Lb *lb, const MsExpr *e) {
    return e->kind == MS_E_NAME && lb->facts->res_kind[e->id] == MS_RES_BINDING &&
           lb_var_owned(lb, lb->facts->res_ref[e->id]);
}

/* Leaves a function that returns nothing. */
void lb_return_void(Lb *lb) {
    const MirValue unit = mir_b_unit(&lb->b);
    lb_own_vars(lb, 0, MIR_NONE);
    lscope_exit_to(&lb->scopes, 0);
    lb_write_back(lb);
    lb_depth(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, unit);
    lb->dead = true;
}

/* A borrowed String leaves the function: an owned name moves out as an owned value. */
static LbVal lb_hand_out(Lb *lb, const MsExpr *e, MirValue v) {
    if (e->kind == MS_E_NAME && lb->facts->res_kind[e->id] == MS_RES_NONE) {
        return la_none_owned(lb, e); // `none` where the holder owns what it holds
    }
    if (lb_names_var(lb, e)) {
        if (mir_b_ty(&lb->b, v) != MIR_STR) {
            lb->ok = false; // a `var` list that leaves is wrapped in an Optional the pass does not make yet
        }
        return (LbVal){v, true}; // a `var` leaves with its current value: lb_own_vars skips it
    }
    if (lb_names_owned(lb, e)) {
        lscope_disown(&lb->scopes, v);
        return (LbVal){v, true};
    }
    if (e->kind == MS_E_NAME) {
        lb->ok = false; // a borrowed parameter handed out as an owned result: left to Rust
        return (LbVal){v, true};
    }
    return (LbVal){lb_copy(lb, v), true}; // a borrowed value that is no local: the caller gets a copy
}

static void lb_return(Lb *lb, const MsStmt *s) {
    if (s->u.expr == NULL) {
        lb_return_void(lb);
        return;
    }
    LbVal value = lb_expr(lb, s->u.expr);
    if (!lb->ok) {
        return;
    }
    const MirTy value_ty = mir_b_ty(&lb->b, value.v);
    if (lb_owns(lb, value_ty) && !value.owned && !lb->b.f.ret_borrowed) {
        value = lb_hand_out(lb, s->u.expr, value.v);
    }
    const bool leaves_var = !lb->b.f.ret_borrowed && lb_names_var(lb, s->u.expr);
    lb_own_temps(lb, lb->stmt_mark);
    lb_own_vars(lb, 0, leaves_var ? value.v : MIR_NONE);
    lscope_exit_to(&lb->scopes, 0);
    lb_write_back(lb);
    lb_depth(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, value.v);
    lb->dead = true;
}


/* Lowers `body` in its own ownership scope, whose end is where control falls out of it. Returns
 * the scope's depth. */
static uint32_t lb_scoped(Lb *lb, const MsStmts *body) {
    const uint32_t depth = lscope_push(&lb->scopes);
    lb_statements(lb, body);
    if (!lb->dead) {
        lb_own_vars(lb, depth, MIR_NONE);
    }
    while (lb->nvars > 0 && lb->vars[lb->nvars - 1].depth >= depth) {
        lb->nvars--;
    }
    lscope_pop(&lb->scopes, !lb->dead);
    return depth;
}

/* Starts emitting into `block`, which some live edge reaches. */
void lb_enter(Lb *lb, MirBlock block) {
    mir_b_switch_to(&lb->b, block);
    lb->dead = false;
}

/* Names the payload an `if name := value` unwrapped. */
static void lb_bind_payload(Lb *lb, const MsPattern *pattern, MirValue payload) {
    lb->value_of[lb->facts->pattern_binding[pattern->id]] = payload;
    lb_name_value(lb, payload, pattern->u.name, false);
}

/* `if cond: then else: else`; the else branch may be empty. */
static void lb_if(Lb *lb, const MsStmt *s) {
    LbVal cond = lb_expr(lb, s->u.branch.cond);
    if (!lb->ok) {
        return;
    }
    const MirValue subject = cond.v; // an `if name := value` unwraps it in the then-branch
    if (s->u.branch.binding != NULL) {
        cond.v = la_test(lb, subject);
    }
    const MirBlock then_block = mir_b_new_block(&lb->b);
    const MirBlock else_block = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    mir_b_br_if(&lb->b, cond.v, then_block, NULL, 0, else_block, NULL, 0);
    mir_b_seal_block(&lb->b, then_block);
    mir_b_seal_block(&lb->b, else_block);
    lb_enter(lb, then_block);
    if (s->u.branch.binding != NULL) {
        lb_bind_payload(lb, s->u.branch.binding, la_payload(lb, subject));
    }
    (void)lb_scoped(lb, &s->u.branch.body);
    const bool then_live = !lb->dead;
    if (then_live) {
        mir_b_br(&lb->b, join, NULL, 0);
    }
    lb_enter(lb, else_block);
    (void)lb_scoped(lb, &s->u.branch.else_body);
    const bool else_live = !lb->dead;
    if (else_live) {
        mir_b_br(&lb->b, join, NULL, 0);
    }
    mir_b_seal_block(&lb->b, join);
    mir_b_switch_to(&lb->b, join);
    lb->dead = !then_live && !else_live;
}

/* `while cond: body`. `while true` leaves only through `return` or a fault. */
static void lb_while(Lb *lb, const MsStmt *s) {
    const MsExpr *cond = s->u.loop.cond;
    const MirBlock header = mir_b_new_block(&lb->b);
    const MirBlock body = mir_b_new_block(&lb->b);
    const MirBlock exit = mir_b_new_block(&lb->b);
    mir_b_br(&lb->b, header, NULL, 0);
    lb_enter(lb, header);
    const bool forever = cond->kind == MS_E_BOOL && cond->u.flag;
    if (forever) {
        mir_b_br(&lb->b, body, NULL, 0);
    } else {
        const LbVal test = lb_expr(lb, cond);
        if (!lb->ok) {
            return;
        }
        mir_b_br_if(&lb->b, test.v, body, NULL, 0, exit, NULL, 0);
    }
    mir_b_seal_block(&lb->b, body);
    lb_enter(lb, body);
    LbLoop here = {header, exit, lb->loop, false, true, lb->scopes.depth};
    lb->loop = &here;
    (void)lb_scoped(lb, &s->u.loop.body);
    lb->loop = here.outer;
    if (!lb->dead) {
        mir_b_br(&lb->b, header, NULL, 0);
    }
    mir_b_seal_block(&lb->b, header);
    mir_b_seal_block(&lb->b, exit);
    lb_enter(lb, exit);
    if (forever && !here.broke) {
        mir_b_unreachable(&lb->b);
        lb->dead = true;
    }
}

/* The block `continue` and the end of the body go to; a `for` makes it on first use. */
static MirBlock lb_step_block(Lb *lb, LbLoop *loop) {
    if (!loop->stepped) {
        loop->next = mir_b_new_block(&lb->b);
        loop->stepped = true;
    }
    return loop->next;
}

/* A call used as a statement: its result is dropped, which only a primitive allows here. */
static void lb_discard(Lb *lb, const MsExpr *call) {
    const LbVal value = lb_expr(lb, call);
    if (lb->ok && value.owned) {
        lb_drop(lb, value.v);
    }
}

/* `break` and `continue`: branch to the loop's exit or header; the rest of the block is dead. */
static void lb_jump(Lb *lb, const MsStmt *s) {
    LbLoop *loop = lb->loop;
    if (loop == NULL) {
        lb->ok = false;
        return;
    }
    if (s->kind == MS_S_BREAK) {
        loop->broke = true;
    }
    lb_own_vars(lb, loop->scope, MIR_NONE);
    lscope_exit_to(&lb->scopes, loop->scope);
    mir_b_br(&lb->b, s->kind == MS_S_BREAK ? loop->exit : lb_step_block(lb, loop), NULL, 0);
    lb->dead = true;
}

/* `name = value` writes the `var` the checker resolved the statement to. */
static void lb_assign(Lb *lb, const MsStmt *s) {
    const uint32_t binding = lb->facts->assign_binding[s->id];
    if (binding == MS_NONE || lb->var_of[binding] == MIR_NONE) {
        lb->ok = false;
        return;
    }
    if (s->u.assign.member_target) {
        lb->ok = false;
        return;
    }
    const MirVar var = lb->var_of[binding];
    const MirValue old = mir_b_use_var(&lb->b, var);
    if (lb_owns(lb, mir_b_ty(&lb->b, old)) && !lb_var_owned(lb, binding)) {
        lb->ok = false; // a `var` String parameter lives in the caller's memory: stored back, not dropped here
        return;
    }
    LbVal value = lb_expr(lb, s->u.assign.value);
    if (!lb->ok) {
        return;
    }
    if (lb_owns(lb, mir_b_ty(&lb->b, old))) {
        if (!value.owned && mir_b_ty(&lb->b, old) != MIR_STR) {
            lb->ok = false; // a list taken from a name: copy or move is not known yet
            return;
        }
        if (!value.owned) {
            value = (LbVal){lb_copy(lb, value.v), true}; // a borrowed String is copied into the variable
        }
        lb_drop(lb, old); // the variable's previous value
    }
    mir_b_def_var(&lb->b, var, value.v);
}

/* `for name in a..b`: a counter from `a` while below `b` (both evaluated once, before the loop),
 * stepped by one after the body or a `continue`. The loop variable is the counter's current value. */
static void lb_for(Lb *lb, const MsStmt *s) {
    if (lb->facts->each_list[s->id]) {
        lst_for(lb, s);
        return;
    }
    const MsExpr *range = s->u.each.iter;
    const LbVal start = lb_expr(lb, range->u.call.args.ptr[0].value);
    const LbVal end = lb->ok ? lb_expr(lb, range->u.call.args.ptr[1].value) : LB_FAIL;
    const uint32_t binding = lb->binding_at[s->id];
    if (!lb->ok || binding == MS_NONE) {
        lb->ok = false;
        return;
    }
    const MirVar counter = mir_b_declare_var(&lb->b, MIR_INT, MM_BORROW);
    mir_b_def_var(&lb->b, counter, start.v);
    const MirBlock header = mir_b_new_block(&lb->b);
    const MirBlock body = mir_b_new_block(&lb->b);
    const MirBlock exit = mir_b_new_block(&lb->b);
    mir_b_br(&lb->b, header, NULL, 0);
    lb_enter(lb, header);
    const MirValue index = mir_b_use_var(&lb->b, counter);
    const MirValue below = mir_b_icmp(&lb->b, MCC_LT, index, end.v);
    mir_b_br_if(&lb->b, below, body, NULL, 0, exit, NULL, 0);
    mir_b_seal_block(&lb->b, body);
    lb_enter(lb, body);
    lb->value_of[binding] = index;
    LbLoop here = {.exit = exit, .outer = lb->loop, .scope = lb->scopes.depth};
    lb->loop = &here;
    (void)lb_scoped(lb, &s->u.each.body);
    lb->loop = here.outer;
    if (!lb->dead) {
        mir_b_br(&lb->b, lb_step_block(lb, &here), NULL, 0);
    }
    if (here.stepped) {
        mir_b_seal_block(&lb->b, here.next);
        lb_enter(lb, here.next);
        const MirValue current = mir_b_use_var(&lb->b, counter);
        mir_b_def_var(&lb->b, counter, mir_b_binop(&lb->b, MOP_IAdd, current, mir_b_iconst(&lb->b, 1)));
        mir_b_br(&lb->b, header, NULL, 0);
    }
    mir_b_seal_block(&lb->b, header);
    mir_b_seal_block(&lb->b, exit);
    lb_enter(lb, exit);
}

/* Lowers a statement; every instruction in it reports the statement's own position, and the
 * enclosing statement's position comes back once it ends. */
static void lb_statement(Lb *lb, const MsStmt *s) {
    const MsStmt *outer = lb->stmt;
    const uint32_t mark = lb->ntemps;
    const uint32_t outer_mark = lb->stmt_mark;
    lb->stmt_mark = mark;
    lb->stmt = s;
    mir_b_set_loc(&lb->b, lb_loc(lb, s->pos));
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND: lb_bind(lb, s); break;
    case MS_S_RETURN: lb_return(lb, s); break;
    case MS_S_IF: lb_if(lb, s); break;
    case MS_S_WHILE: lb_while(lb, s); break;
    case MS_S_ASSIGN: lb_assign(lb, s); break;
    case MS_S_BREAK:
    case MS_S_CONTINUE: lb_jump(lb, s); break;
    case MS_S_FOR: lb_for(lb, s); break;
    case MS_S_CALL: lb_discard(lb, s->u.expr); break;
    }
    if (lb->ok && !lb->dead) {
        lb_release_temps(lb, mark);
    }
    lb->ntemps = mark < lb->ntemps ? mark : lb->ntemps;
    lb->stmt_mark = outer_mark;
    lb->stmt = outer;
    if (outer != NULL) {
        mir_b_set_loc(&lb->b, lb_loc(lb, outer->pos));
    }
}

void lb_statements(Lb *lb, const MsStmts *body) {
    for (uint32_t i = 0; i < body->len && lb->ok && !lb->dead; i++) {
        lb_statement(lb, body->ptr[i]);
    }
}

/* ---- functions ---- */

/* The function's MIR signature into `params` (one per source parameter) and `ret`; false when a
 * parameter or the result is not a type this pass handles. */
static bool lb_signature(Lb *lb, const MsFunc *fn, MsSymId sym, MirParam *params, MirTy *ret) {
    const MsTy sig = lb->c->syms.ty[sym];
    const MsTyParam *sig_params = ms_ty_params(&lb->c->tys, sig);
    const MsTy result = lb->c->tys.result[sig];
    *ret = result == lb->void_ty ? MIR_VOID : lb_mir_ty(lb, result);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MirTy ty = lb_mir_ty(lb, sig_params[i].ty);
        const bool moving = lb_param_moves(lb, lb->c->syms.decl[sym], i);
        if (ty == MIR_NONE || (moving && !lb_owns(lb, ty)) || (fn->params.ptr[i]->is_mutable && lb_is_fn(lb, ty))) { // only a String is handed over so far
            return false;
        }
        params[i] = (MirParam){fn->params.ptr[i]->is_mutable ? MIR_PTR : ty, moving ? MM_MOVE : MM_BORROW};
    }
    return *ret != MIR_NONE;
}

/* The indexes of the `var` parameters, which no other memory overlaps (the text form's `noalias`). */
static void lb_mark_noalias(Lb *lb, const MsFunc *fn) {
    uint32_t count = 0;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        count += fn->params.ptr[i]->is_mutable ? 1 : 0;
    }
    if (count == 0) {
        return;
    }
    uint32_t *indexes = MS_NEW_N(&lb->m->arena, uint32_t, count);
    uint32_t next = 0;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->is_mutable) {
            indexes[next++] = i;
        }
    }
    lb->b.f.noalias = indexes;
    lb->b.f.nnoalias = count;
}

/* Starts the function and binds its parameters; false when its signature is not handled. */
static bool lb_begin(Lb *lb, const MsDecl *d, MsSymId sym) {
    const MsFunc *fn = &d->u.fn;
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, fn->params.len + 1);
    MirTy ret = MIR_NONE;
    if (!lb_signature(lb, fn, sym, params, &ret)) {
        return false;
    }
    const MsStr name = ms_name(lb->c->names, fn->name);
    mir_b_init(&lb->b, lb->m, lb->has_override ? lb->name_override : mir_name(lb->m, name.ptr, name.len), params,
               fn->params.len, ret);
    lb->b.f.loc = lb_loc(lb, d->pos);
    lb->b.f.ret_borrowed = lb->facts->ret_borrowed[d->id]; // every result is a reference into the arguments
    lb_mark_noalias(lb, fn);
    MirValue *values = MS_NEW_N(&lb->m->arena, MirValue, fn->params.len + 1);
    mir_b_params(&lb->b, values, fn->params.len);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const uint32_t binding = lb->binding_at[fn->params.ptr[i]->id];
        lb->value_of[binding] = values[i];
        if (!fn->params.ptr[i]->is_mutable) { // Rust names no `var` parameter: its value is a pointer
            lb_name_value(lb, values[i], fn->params.ptr[i]->name, true);
        }
    }
    lb_depth(lb, MOP_DepthEnter);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->is_mutable) {
            const uint32_t binding = lb->binding_at[fn->params.ptr[i]->id];
            const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[binding]);
            lb->var_of[binding] = mir_b_declare_var(&lb->b, ty, MM_BORROW);
            mir_b_def_var(&lb->b, lb->var_of[binding], lb_load(lb, values[i], ty));
        }
    }
    return true;
}

/* The state of a body about to be lowered: its builder is started and `lb->decl` is set. */
void lb_reset_state(Lb *lb) {
    lb->dead = false;
    lb->loop = NULL;
    lb->stmt = NULL;
    lscope_init(&lb->scopes, &lb->b);
    lb->vars = NULL; // the arena they live in is freed between passes
    lb->nvars = lb->cvars = 0;
    lb->temps = NULL;
    lb->ntemps = lb->ctemps = lb->stmt_mark = lb->branching = 0;
    (void)lscope_push(&lb->scopes); // the body's own scope: depth 0
}

/* Lowers one checked function over its stub `slot` in the module; false when it is not handled. */
static bool lb_function(Lb *lb, const MsDecl *d, MsSymId sym, uint32_t slot) {
    lb->decl = d;
    lb->closure = false;
    lb->jobs = NULL; // the arena they live in is freed between passes
    lb->njobs = lb->cjobs = 0;
    lb->ok = lb_begin(lb, d, sym);
    if (!lb->ok) {
        return false;
    }
    lb_reset_state(lb);
    for (uint32_t i = 0; i < d->u.fn.params.len; i++) {
        if (lb_param_moves(lb, d, i)) { // the function owns what it was handed
            lscope_own(&lb->scopes, lb->value_of[lb->binding_at[d->u.fn.params.ptr[i]->id]], 0);
        }
    }
    lb_statements(lb, &d->u.fn.body);
    if (lb->ok && !lb->dead && lb->b.f.ret == MIR_VOID) {
        lb_return_void(lb); // the end of a function that returns nothing
    }
    lb->ok = lb->ok && lb->dead;
    MirFunc f = {0};
    if (lb->ok) {
        mir_func_compact_blocks(&lb->b.f); // unreachable blocks go; the rest in reverse post-order
        const MsStr name = ms_name(lb->c->names, d->u.fn.name);
        const bool is_main = name.len == 4 && memcmp(name.ptr, "main", 4) == 0;
        if (is_main && lb->b.f.ret == MIR_INT) { // any other `main` gets a wrapper, which is the export
            lb->b.f.linkage = ML_EXPORT;
        }
    }
    // Finishing also frees the builder's scratch tables, which a failed function needs too.
    const bool built = mir_b_into_func(&lb->b, &f);
    if (lb->ok && built) {
        lb->m->funcs[slot] = f;
    }
    return lb_closures(lb, lb->ok && built); // the lambdas it made are lowered after it
}

static void lb_index_bindings(Lb *lb, MsArena *arena) {
    const MsBindings *bindings = &lb->facts->bindings;
    const size_t nodes = (size_t)lb->facts->node_count + 1;
    lb->binding_at = MS_NEW_N(arena, uint32_t, nodes);
    memset(lb->binding_at, 0xff, nodes * sizeof *lb->binding_at);
    for (uint32_t i = 0; i < bindings->count; i++) {
        lb->binding_at[bindings->decl_node[i]] = i;
    }
    lb->type_of = MS_NEW_N(arena, MirTy, lb->c->tys.count + 1);
    memset(lb->type_of, 0xff, (lb->c->tys.count + 1) * sizeof *lb->type_of);
    lb->value_of = MS_NEW_N(arena, MirValue, bindings->count + 1);
    lb->var_of = MS_NEW_N(arena, MirVar, bindings->count + 1);
    memset(lb->var_of, 0xff, (bindings->count + 1) * sizeof *lb->var_of);
    memset(lb->value_of, 0xff, (bindings->count + 1) * sizeof *lb->value_of);
}

/* Adds a function with the declared signature and an empty body, so calls can name it before its
 * body is lowered (recursion and any order of declarations). */
static uint32_t lb_add_stub(Lb *lb, const MsDecl *d, MsSymId sym) {
    const MsFunc *fn = &d->u.fn;
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, fn->params.len + 1);
    MirTy ret = MIR_NONE;
    if (!lb_signature(lb, fn, sym, params, &ret)) {
        return MIR_NONE;
    }
    const MsStr name = ms_name(lb->c->names, fn->name);
    MirFunc stub = {0};
    mir_func_init(lb->m, &stub, lb->has_override ? lb->name_override : mir_name(lb->m, name.ptr, name.len), params,
                  fn->params.len, ret);
    stub.ret_borrowed = lb->facts->ret_borrowed[d->id]; // callers read it before the body is lowered
    return mir_add_func(lb->m, &stub);
}

/* ---- generic instances ---- */

static LbInst *lb_find_inst(LbInst *list, uint32_t n, MsSymId sym, const MsTy *args, uint32_t nargs) {
    for (uint32_t i = 0; i < n; i++) {
        if (list[i].sym == sym && list[i].nargs == nargs && memcmp(list[i].args, args, nargs * sizeof *args) == 0) {
            return &list[i];
        }
    }
    return NULL;
}

static bool lb_push_inst(LbInst **list, uint32_t *n, uint32_t *cap, const LbInst *inst) {
    if (*n == *cap) {
        const uint32_t grown = *cap == 0 ? 8 : *cap * 2;
        LbInst *bigger = realloc(*list, (size_t)grown * sizeof **list);
        if (bigger == NULL) {
            return false;
        }
        *list = bigger;
        *cap = grown;
    }
    (*list)[(*n)++] = *inst;
    return true;
}

/* The copy of the generic function `sym` for `args`, created (with its signature and an empty body)
 * on first use; MIR_NONE when its signature is not handled or it failed before. Copies are named
 * `name`, `name.1`, `name.2`, ... in the order they are created. Their bodies are lowered by
 * `lb_drain_instances` once the module's own functions are. */
static uint32_t lb_instance(Lb *lb, MsSymId sym, const MsTy *args, uint32_t nargs) {
    if (lb_find_inst(lb->dead_insts, lb->ndead_insts, sym, args, nargs) != NULL) {
        return MIR_NONE;
    }
    const LbInst *known = lb_find_inst(lb->insts, lb->ninsts, sym, args, nargs);
    if (known != NULL) {
        return known->func;
    }
    LbInst inst = {.sym = sym, .nargs = nargs, .func = MIR_NONE};
    memcpy(inst.args, args, nargs * sizeof *args);
    const MsDecl *d = lb->c->syms.decl[sym];
    const MsDef *def = ms_def(lb->mut, sym);
    if (d == NULL || d->kind != MS_D_FN || def == NULL || def->nvars != nargs || !lb->facts->body_checked[d->id]) {
        (void)lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst);
        return MIR_NONE;
    }
    uint32_t serial = 0;
    for (uint32_t i = 0; i < lb->ninsts; i++) {
        serial += lb->insts[i].sym == sym ? 1 : 0;
    }
    const MsStr base = ms_name(lb->c->names, d->u.fn.name);
    char *text = MS_NEW_N(&lb->m->arena, char, base.len + 16);
    const int len = serial == 0 ? snprintf(text, base.len + 16, "%.*s", (int)base.len, base.ptr)
                                : snprintf(text, base.len + 16, "%.*s.%u", (int)base.len, base.ptr, serial);
    const MsTy *saved_vars = lb->sub_vars, *saved_args = lb->sub_args;
    const uint32_t saved_n = lb->nsub;
    const bool saved_override = lb->has_override;
    const MsSym saved_name = lb->name_override;
    lb->sub_vars = def->vars;
    lb->sub_args = inst.args;
    lb->nsub = nargs;
    lb->has_override = true;
    lb->name_override = mir_name(lb->m, text, (size_t)len);
    inst.func = lb_add_stub(lb, d, sym);
    lb->sub_vars = saved_vars;
    lb->sub_args = saved_args;
    lb->nsub = saved_n;
    lb->has_override = saved_override;
    lb->name_override = saved_name;
    if (inst.func == MIR_NONE) {
        (void)lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst);
        return MIR_NONE;
    }
    if (!lb_push_inst(&lb->insts, &lb->ninsts, &lb->cinsts, &inst)) {
        lb->ok = false;
        return MIR_NONE;
    }
    return inst.func;
}

/* Lowers the body of every copy created so far, and those the bodies create in turn. A copy that
 * does not lower is remembered as dead: the next pass makes its callers fail. True when one died. */
static bool lb_drain_instances(Lb *lb, uint32_t *lowered) {
    bool died = false;
    for (uint32_t i = 0; i < lb->ninsts; i++) {
        const LbInst inst = lb->insts[i]; // the list may grow while the body is lowered
        lb->sub_vars = ms_def(lb->mut, inst.sym)->vars;
        lb->sub_args = inst.args;
        lb->nsub = inst.nargs;
        lb->has_override = true;
        lb->name_override = lb->m->funcs[inst.func].name;
        const bool done = lb_function(lb, lb->c->syms.decl[inst.sym], inst.sym, inst.func);
        *lowered += done ? 1 : 0;
        if (!done) {
            died = lb_push_inst(&lb->dead_insts, &lb->ndead_insts, &lb->cdead_insts, &inst) || died;
        }
    }
    lb->nsub = 0;
    lb->has_override = false;
    return died;
}

/* Whether the checker reported anything inside declaration `index`: on lines from its own to the
 * next declaration's. A program with a diagnostic does not build, so such a function is not
 * lowered (its body may be ill-typed). */
static bool lb_has_diagnostic(const MsModuleRow *row, uint32_t index) {
    const uint32_t first = row->syntax->decls[index]->pos.line;
    const uint32_t end = index + 1 < row->syntax->ndecls ? row->syntax->decls[index + 1]->pos.line : UINT32_MAX;
    for (uint32_t k = 0; k < row->ndiags; k++) {
        const uint32_t line = row->diags[k].diag.pos.line;
        if (line >= first && line < end) {
            return true;
        }
    }
    return false;
}

/* One pass over the module's checked functions: stub each one not in `failed`, then lower them.
 * A function that does not lower is marked in `failed`; true when any new one was. */
static bool lb_pass(Lb *lb, MsModId module, bool *failed, uint32_t *lowered) {
    const MsModuleRow *row = &lb->c->mods[module];
    const uint32_t ndecls = row->syntax->ndecls;
    memset(lb->func_of, 0xff, (size_t)lb->c->syms.count * sizeof *lb->func_of);
    memset(lb->thunk_of, 0xff, (size_t)lb->c->syms.count * sizeof *lb->thunk_of);
    MsSymId *syms = MS_NEW_N(&lb->m->arena, MsSymId, (size_t)ndecls + 1);
    for (uint32_t i = 0; i < ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool checked = d->kind == MS_D_FN && lb->facts->body_checked[d->id] && !failed[i] && !lb_has_diagnostic(row, i);
        syms[i] = checked ? ms_decl_own_symbol(lb->c, module, d) : MS_NONE;
        if (syms[i] != MS_NONE && lb->c->syms.nvars[syms[i]] != 0) {
            syms[i] = MS_NONE; // a generic function is checked here but not lowered: it needs one copy per type argument
        }
        if (syms[i] != MS_NONE) {
            lb->func_of[syms[i]] = lb_add_stub(lb, d, syms[i]);
        }
    }
    bool changed = false;
    *lowered = 0;
    lb->ninsts = 0;
    for (uint32_t i = 0; i < ndecls; i++) {
        if (syms[i] == MS_NONE) {
            continue;
        }
        const bool unlowerable = lb->func_of[syms[i]] == MIR_NONE;
        const bool done = !unlowerable && lb_function(lb, row->syntax->decls[i], syms[i], lb->func_of[syms[i]]);
        failed[i] = !done;
        changed = changed || !done;
        *lowered += done ? 1 : 0;
    }
    return lb_drain_instances(lb, lowered) || changed;
}

/* A failed function leaves a stub, and calls to it were lowered against it, so the pass repeats
 * without it (its callers then fail too) until a pass loses nothing. That is at most one pass per
 * function; programs lose a function or two. */
uint32_t ms_lower_module(MsCheck *c, MsModId module, MirModule *out) {
    const MsModuleRow *row = &c->mods[module];
    const MsFacts *facts = row->facts;
    if (facts == NULL || facts->body_checked == NULL) {
        return 0;
    }
    Lb lb = {.c = c,
             .mut = c,
             .facts = facts,
             .m = out,
             .int_ty = lb_primitive(c, "Int"),
             .float_ty = lb_primitive(c, "Float"),
             .bool_ty = lb_primitive(c, "Bool"),
             .string_ty = lb_primitive(c, "String"),
             .void_ty = lb_primitive(c, "Void")};
    lb.classifier = ms_classifier_new(c);
    ms_classifier_mark_methods(lb.classifier, facts->methods);
    bool *failed = calloc((size_t)row->syntax->ndecls + 1, sizeof *failed);
    lb.func_of = calloc((size_t)c->syms.count + 1, sizeof *lb.func_of);
    lb.thunk_of = calloc((size_t)c->syms.count + 1, sizeof *lb.thunk_of);
    uint32_t lowered = 0;
    while (failed != NULL && lb.func_of != NULL && lb.thunk_of != NULL) {
        mir_module_free(out);
        mir_module_init(out);
        lb_index_bindings(&lb, &out->arena);
        if (!lb_pass(&lb, module, failed, &lowered)) {
            break;
        }
    }
    ms_classifier_free(lb.classifier);
    free(lb.func_of);
    free(lb.insts);
    free(lb.dead_insts);
    free(lb.thunk_of);
    free(failed);
    return lowered;
}
