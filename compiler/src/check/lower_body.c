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

#include "ms/parse.h"
#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"
#include "ms/lower.h"
#include "ms/lower_internal.h"
#include "ms/rt_ops.h"
#include "ms/lower_scope.h"
#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"
#include "ms/ty_algebra.h"

LbVal lb_unsupported_at(Lb *lb, const char *site, int line) {
    if (lb->ok) { // the first refusal is the reason; the rest follow from it
        lb->fail_site = site;
        lb->fail_line = line;
        lb->fail_stmt = lb->stmt;
    }
    lb->ok = false;
    return LB_FAIL;
}

/* `ty` as the function being lowered sees it: the variables of the instance are the types they
 * stand for, through arguments, parameters and results (`List[T]` becomes `List[Int]`). A variable
 * is matched by id, as the checker's substitution does. */
MsTy lb_ty(Lb *lb, MsTy ty) {
    if (lb->nsub == 0 || ty == MS_TY_NONE) {
        return ty;
    }
    if (!ms_ty_has_variable(&lb->c->tys, ty)) {
        return ty;
    }
    MsArena scratch = {0};
    const MsTySubst subst = {lb->sub_vars, lb->sub_args, lb->nsub};
    const MsTy result = ms_ty_subst(&lb->mut->tys, &scratch, ty, &subst);
    ms_arena_free(&scratch);
    return result;
}

/* A record, Optional or Result type. */
static MirTy lb_mir_aggregate(Lb *lb, MsTy ty) {
    const MirTy record = lr_type(lb, ty);
    if (record != MIR_NONE) {
        return record;
    }
    const MirTy user_enum = le_type(lb, ty);
    if (user_enum != MIR_NONE) {
        return user_enum;
    }
    const MirTy iface = li_type(lb, ty);
    return iface != MIR_NONE ? iface : la_type(lb, ty);
}

static MirTy lb_mir_alt(Lb *lb, MsTy ty) {
    const MirTy mir = lb_mir_aggregate(lb, ty);
    if (mir != MIR_NONE && ms_classify(lb->classifier, ty) == MS_CLASS_RESOURCE) {
        lc_register(lb, ty, mir);
    }
    return mir;
}

/* The MIR type of a checker type this pass handles, or MIR_NONE. */
/* The sized numbers, by the standard type the checker knows them as. */
static const struct {
    MsBuiltin builtin;
    MirTy mir;
} lb_sized_numbers[] = {
    {MS_BI_INT8, MIR_INT8},     {MS_BI_INT16, MIR_INT16},   {MS_BI_INT32, MIR_INT32},   {MS_BI_UINT8, MIR_UINT8},
    {MS_BI_UINT16, MIR_UINT16}, {MS_BI_UINT32, MIR_UINT32}, {MS_BI_UINT64, MIR_UINT64}, {MS_BI_FLOAT32, MIR_FLOAT32},
};

MirTy lb_mir_ty(Lb *lb, MsTy ty) {
    ty = lb_ty(lb, ty);
    for (size_t i = 0; i < sizeof lb_sized_numbers / sizeof lb_sized_numbers[0]; i++) {
        if (ms_ty_is(&lb->c->tys, ty, lb_sized_numbers[i].builtin)) {
            return lb_sized_numbers[i].mir;
        }
    }
    if (ms_ty_is(&lb->c->tys, ty, MS_BI_BYTES)) {
        return MIR_BYTES;
    }
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
    if (ms_classify(lb->classifier, ty) == MS_CLASS_RESOURCE && !lc_has_closer(lb, ty)) {
        return MIR_NONE; // a value that closes but not by a close of its own: left to the Rust lowering
    }
    const MirTy list = lst_type(lb, ty);
    if (list != MIR_NONE) {
        return list;
    }
    const MirTy map = lm_type(lb, ty);
    if (map != MIR_NONE) {
        return map;
    }
    const MirTy native = lx_type(lb, ty);
    return native != MIR_NONE ? native : lb_mir_alt(lb, ty);
}

MirLoc lb_loc(const Lb *lb, MsPos pos) {
    return (MirLoc){.file = lb->views[lb->view].file, .line = pos.line, .col = pos.column, .scope = lb->b.loc.scope};
}

void lb_emit_plain(Lb *lb, MirOp op) {
    (void)mir_b_emit(&lb->b, op, NULL, 0, (MirImm){0}, MIR_NONE);
}

/* `depth.enter` and `depth.leave` bracket a function; a closure body has neither. */
void lb_depth(Lb *lb, MirOp op) {
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
    return ty != MIR_NONE && (ty == MIR_STR || lb_is_fn(lb, ty) || mir_needs_drop(lb->m, ty) || lc_is_resource(lb, ty));
}

/* An owned temporary of the statement: dropped where the statement ends, newest first. Where no such
 * end exists (inside a condition, an arm or the right side of `and`/`or`) it is dropped now. */
void lb_hold_temp(Lb *lb, MirValue v) {
    const bool simple = lb->stmt != NULL && lb->branching == 0 &&
                        (lb->stmt->kind == MS_S_BIND || lb->stmt->kind == MS_S_RETURN ||
                         lb->stmt->kind == MS_S_ASSIGN || lb->stmt->kind == MS_S_CALL || lb->stmt->kind == MS_S_IF);
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
MirValue lb_copy(Lb *lb, MirValue v) {
    const MirImm one = {.tag = MI_INT, .i = 1};
    return mir_b_emit(&lb->b, MOP_Clone, &v, 1, one, mir_b_ty(&lb->b, v));
}

/* A module constant has no statements to give its instructions a position: each expression sets its
 * own as it starts, and the position stays until the next one starts (an operator sets it again once
 * its operands are evaluated), as in the Rust lowering. */
void lb_at_expression(Lb *lb, const MsExpr *e) {
    if (lb->cur.value != NULL) {
        mir_b_set_loc(&lb->b, lb_loc(lb, e->pos));
    }
}

/* ---- literals ---- */

/* The register value of the number literal `e` at the type `ty`, negated or not: a float's bits, or
 * the integer. A `Float32` literal rounds once, from its text, to binary32. */
int64_t lb_number_bits(Lb *lb, const MsExpr *e, MirTy ty, bool negate) {
    const MsStr text = ms_number_canonical(&lb->m->arena, ms_name(lb->c->names, e->u.sym));
    char *digits = ms_arena_strndup(&lb->m->arena, text.ptr, text.len);
    if (ty == MIR_FLOAT || ty == MIR_FLOAT32) {
        const double value = ty == MIR_FLOAT32 ? (double)strtof(digits, NULL) : strtod(digits, NULL);
        const double signed_value = negate ? -value : value;
        int64_t bits = 0;
        memcpy(&bits, &signed_value, sizeof signed_value);
        return bits;
    }
    const uint64_t magnitude = strtoull(digits, NULL, 10);
    /* Negated as an unsigned value: the magnitude of Int.min does not fit a signed one. */
    return (int64_t)(negate ? 0 - magnitude : magnitude);
}

static LbVal lb_number(Lb *lb, const MsExpr *e, bool negate) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const int64_t bits = lb_number_bits(lb, e, ty, negate);
    if (ty == MIR_FLOAT || ty == MIR_FLOAT32) {
        return (LbVal){mir_b_emit(&lb->b, MOP_FConst, NULL, 0, (MirImm){.tag = MI_FLOAT, .i = bits}, ty), false};
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = bits}, ty == MIR_NONE ? MIR_INT : ty), false};
}

/* A literal, an interpolation of one value, or a join of several pieces. */
static LbVal lb_text(Lb *lb, const MsExpr *e) {
    if (e->u.text.len > 1) {
        return lt_text(lb, e); // an interpolation joins its pieces
    }
    if (e->u.text.len != 1) {
        return LB_UNSUPPORTED(lb);
    }
    if (e->u.text.ptr[0].expr != NULL) {
        return lt_single(lb, e->u.text.ptr[0].expr);
    }
    const MsStr lit = e->u.text.ptr[0].lit;
    MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
    return (LbVal){mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false};
}

/* ---- names ---- */

/* A `var` parameter arrives as a pointer to the caller's variable. The body works on a copy held
 * in an SSA variable: it is loaded on entry and stored back before every return (`noalias` says
 * nothing else touches the memory meanwhile). */
MirValue lb_load(Lb *lb, MirValue slot, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
}

void lb_store(Lb *lb, MirValue slot, MirValue value) {
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
        return facts->res_kind[e->id] == MS_RES_NONE ? la_none(lb, e) : LB_UNSUPPORTED(lb);
    }
    if (facts != lb->views[lb->view].facts) {
        return LB_UNSUPPORTED(lb); // a field default read under its declaring module's facts: no local of this function is in scope there
    }
    const uint32_t binding = facts->res_ref[e->id];
    if (lb->var_of[binding] != MIR_NONE) {
        return (LbVal){mir_b_use_var(&lb->b, lb->var_of[binding]), false};
    }
    MirValue held;
    if (lc_is_slot_local(lb, binding)) { // a resource lives in its slot and is read from it
        const bool moved = facts->moved_out[e->id];
        if (!lc_use(lb, binding, &held, moved)) {
            return LB_UNSUPPORTED(lb);
        }
        return (LbVal){held, moved}; // a moved value belongs to its new owner
    }
    if (lb->value_of[binding] == MIR_NONE) {
        return LB_UNSUPPORTED(lb); // a name no statement of this function bound: a field default naming a sibling field
    }
    return (LbVal){lb->value_of[binding], false};
}

/* ---- operators ---- */

static LbVal lb_match(Lb *lb, const MsExpr *e);

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
uint32_t lb_string_concat(Lb *lb) {
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
        return LB_UNSUPPORTED(lb);
    }
    const MirOp mir_op = ty == MIR_FLOAT ? MOP_FCmp : MOP_ICmp;
    MirValue result = mir_b_emit(&lb->b, mir_op, args, 2, cc, MIR_BOOL);
    if (op == MS_B_NE) {
        result = mir_b_emit(&lb->b, MOP_Not, &result, 1, (MirImm){0}, MIR_BOOL);
    }
    return (LbVal){result, false};
}

/* The runtime function of `left op right` on a big integer or decimal (`prefix` names which), or NULL when the runtime
 * has none for `op` (a comparison, or `%` of a decimal). */
static const MsRtFn *lb_number_operator(MsBinaryOp op, bool decimal) {
    const char *symbol = NULL;
    switch (op) {
    case MS_B_ADD: symbol = decimal ? "msstd_decimal_add" : "msstd_bigint_add"; break;
    case MS_B_SUB: symbol = decimal ? "msstd_decimal_subtract" : "msstd_bigint_subtract"; break;
    case MS_B_MUL: symbol = decimal ? "msstd_decimal_multiply" : "msstd_bigint_multiply"; break;
    case MS_B_DIV: symbol = decimal ? "msstd_decimal_divide" : "msstd_bigint_quotient"; break;
    case MS_B_REM: symbol = decimal ? NULL : "msstd_bigint_modulo"; break;
    default: break;
    }
    return symbol == NULL ? NULL : ms_rt_fn_find(symbol, strlen(symbol));
}

/* Arithmetic on big integers and decimals, which the runtime performs; the operands are borrowed and their owned
 * temporaries are released at the end of the statement. */
static LbVal lb_number_apply(Lb *lb, MsBinaryOp op, LbVal left, LbVal right, bool decimal) {
    const MsRtFn *fn = lb_number_operator(op, decimal);
    if (fn == NULL) {
        return LB_UNSUPPORTED(lb);
    }
    const MirValue args[2] = {left.v, right.v};
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    LbVal result;
    if (decimal) { // an operator hands the decimals over by value; a method call stores them in slots first
        const MirTy types[2] = {ty, ty};
        result = (LbVal){mir_b_call_rt(&lb->b, lb_runtime_extern(lb, fn->symbol, types, 2, ty, MR_NONE, fn->pure), args, 2), false};
    } else {
        result = lb_native_call(lb, fn, args, 2, ty);
    }
    for (uint32_t i = 0; lb->ok && i < 2; i++) {
        if ((i == 0 ? left : right).owned) {
            lb_hold_temp(lb, args[i]);
        }
    }
    return result;
}

/* Whether `ty` is the runtime's big integer (`decimal` false) or decimal (true). */
static bool lb_is_number_type(const Lb *lb, MirTy ty, bool decimal) {
    const MirTyData *data = mir_ty_data(lb->m, ty);
    MsSym name = MS_NONE;
    if (!decimal && data->kind == MK_OBJ) {
        name = data->name;
    } else if (decimal && data->kind == MK_TYPE) {
        name = lb->m->type_defs[data->id].name;
    } else {
        return false;
    }
    const MsStr text = ms_name(&lb->m->names, name);
    const char *want = decimal ? "Decimal" : "BigInt";
    return text.len == strlen(want) && memcmp(text.ptr, want, text.len) == 0;
}

/* Whether `ty` is a sized integer (`Int8` to `UInt32`, not the unsigned 64-bit `UInt64` with its own instructions): its sum, difference, product and order are the checked instructions. */
static bool lb_is_sized_int(MirTy ty) {
    return ty == MIR_INT8 || ty == MIR_INT16 || ty == MIR_INT32 || ty == MIR_UINT8 || ty == MIR_UINT16 || ty == MIR_UINT32;
}

/* `left op right` on lowered operands (not `and` and `or`, which short-circuit). */
static LbVal lb_apply(Lb *lb, MsBinaryOp op, LbVal left, LbVal right) {
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    if (op == MS_B_ADD && ty == MIR_STR) {
        return lb_concat(lb, left, right);
    }
    if (lb_is_number_type(lb, ty, false) || lb_is_number_type(lb, ty, true)) {
        return lb_number_apply(lb, op, left, right, lb_is_number_type(lb, ty, true));
    }
    const bool sized = lb_is_sized_int(ty);
    const bool divides = op == MS_B_DIV || op == MS_B_REM;
    if (lb_owns(lb, ty) || (ty != MIR_INT && ty != MIR_FLOAT && ty != MIR_BOOL && !sized) || (sized && divides)) {
        return LB_UNSUPPORTED(lb); // sized division and the other native types' operations are not lowered yet
    }
    const MirOp arithmetic = lb_arithmetic_op(op, ty);
    if (arithmetic == MOP_COUNT) {
        return lb_compare(lb, op, left, right);
    }
    return (LbVal){mir_b_binop(&lb->b, arithmetic, left.v, right.v), false};
}

/* The text of a string literal `str.eq_lit` can compare with (1 to 8 bytes, no NUL), else a null pointer. */
static MsStr lb_literal_text(const MsExpr *e) {
    const bool plain = e->kind == MS_E_TEXT && e->u.text.len == 1 && e->u.text.ptr[0].expr == NULL;
    const MsStr lit = plain ? e->u.text.ptr[0].lit : (MsStr){0};
    return lit.len >= 1 && lit.len <= 8 && memchr(lit.ptr, '\0', lit.len) == NULL ? lit : (MsStr){0};
}

/* `a == b` and `a != b` on Strings: a comparison with a literal is `str.eq_lit` (the right literal wins),
 * any other is the runtime's `string_eq`. An operand that is a temporary is dropped after it. */
static LbVal lb_string_equal(Lb *lb, const MsExpr *e) {
    const LbVal left = lb_expr(lb, e->u.bin.left);
    const LbVal right = lb->ok ? lb_expr(lb, e->u.bin.right) : LB_FAIL;
    lb_at_expression(lb, e); // the operator, after its operands
    if (!lb->ok) {
        return LB_FAIL;
    }
    MirValue same = MIR_NONE;
    const bool literal_right = lb_literal_text(e->u.bin.right).ptr != NULL;
    const MsStr lit = lb_literal_text(literal_right ? e->u.bin.right : e->u.bin.left);
    if (lit.ptr != NULL) {
        const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
        const MirValue other = literal_right ? left.v : right.v;
        same = mir_b_emit(&lb->b, MOP_StrEqLit, &other, 1, imm, MIR_BOOL);
    } else {
        const struct MsRtFn *fn = lb_native_function(lb, lb->string_ty, ms_intern_cstr(lb->c->names, "eq"));
        const MirValue args[2] = {left.v, right.v};
        const LbVal call = fn == NULL ? LB_FAIL : lb_native_call(lb, fn, args, 2, MIR_BOOL);
        if (fn == NULL || !lb->ok) {
            return LB_UNSUPPORTED(lb);
        }
        same = call.v;
    }
    if (right.owned) { // an operand that is a temporary is dropped after the comparison, the right one first
        lb_drop(lb, right.v);
    }
    if (left.owned) {
        lb_drop(lb, left.v);
    }
    if (e->op == MS_B_NE) {
        same = mir_b_emit(&lb->b, MOP_Not, &same, 1, (MirImm){0}, MIR_BOOL);
    }
    return (LbVal){same, false};
}

static LbVal lb_binary(Lb *lb, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    if (op == MS_B_AND || op == MS_B_OR) {
        return lb_short_circuit(lb, e);
    }
    if ((op == MS_B_EQ || op == MS_B_NE) && lb->facts->expr_ty[e->u.bin.left->id] == lb->string_ty) {
        return lb_string_equal(lb, e);
    }
    if (op == MS_B_ADD && lb->facts->expr_ty[e->id] == lb->string_ty) {
        return lt_text(lb, e); // a chain of string sums is one join
    }
    const LbVal left = lb_expr(lb, e->u.bin.left);
    const LbVal right = lb->ok ? lb_expr(lb, e->u.bin.right) : LB_FAIL;
    lb_at_expression(lb, e); // the operator, after its operands
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (mir_b_ty(&lb->b, left.v) != mir_b_ty(&lb->b, right.v)) {
        return LB_UNSUPPORTED(lb); // an Optional beside the plain value it wraps
    }
    if ((op == MS_B_EQ || op == MS_B_NE) && lb_is_aggregate(lb, mir_b_ty(&lb->b, left.v))) {
        return lq_equal(lb, left, right, op == MS_B_NE);
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
        (void)LB_UNSUPPORTED(lb);
        return MIR_NONE;
    }
    const uint32_t binding = lb->facts->res_ref[arg->id];
    *binding_out = binding;
    if (lb->var_of[binding] == MIR_NONE) {
        (void)LB_UNSUPPORTED(lb);
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
bool lb_has_self(const LbCallable *c) {
    return c->self_ty != MS_TY_NONE;
}

/* The parameters of a callable in call order: the receiver (a method's) first. */
uint32_t lb_slots(const LbCallable *c) {
    return c->fn == NULL ? 0u : c->fn->params.len + (lb_has_self(c) ? 1u : 0u);
}

/* The source parameter behind a slot: NULL for a method's receiver. */
const MsParam *lb_slot_param(const LbCallable *c, uint32_t slot) {
    const uint32_t first = lb_has_self(c) ? 1u : 0u;
    return slot < first ? NULL : c->fn->params.ptr[slot - first];
}

bool lb_slot_mutable(const LbCallable *c, uint32_t slot) {
    const MsParam *param = lb_slot_param(c, slot);
    return param == NULL ? c->mutating : param->is_mutable;
}

/* The node whose binding a parameter slot introduces: a method's node for its `self`. */
uint32_t lb_slot_node(const LbCallable *c, uint32_t slot) {
    const MsParam *param = lb_slot_param(c, slot);
    return param == NULL ? c->node : param->id;
}

bool lb_param_moves(const Lb *lb, const LbCallable *c, uint32_t slot) {
    const MsParam *param = lb_slot_param(c, slot);
    const bool declared = param != NULL && param->moving;
    return declared || (slot == 0 && lb_has_self(c) && c->consuming) || ((lb->facts->param_consumed[c->node] >> slot) & 1u) != 0;
}

/* Whether `e` names a `let` local, a payload an arm took out of its scrutinee or a `move` parameter: a value the function owns, so using it
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
    for (uint32_t i = 0; i < lb->nparts; i++) {
        if (lb->parts[i] == binding) {
            return true; // a payload the arm took out of its scrutinee
        }
    }
    for (uint32_t i = 0; i < lb_slots(&lb->cur); i++) {
        if (lb->binding_at[lb_slot_node(&lb->cur, i)] == binding) {
            return lb_param_moves(lb, &lb->cur, i);
        }
    }
    return false;
}

/* A call of a module function the checker resolved; a callee that is not lowered (no `func_of`)
 * fails the caller with it. */
/* A `move` argument: an owned temporary is handed over as it is, an owned name moves out of its
 * scope, and anything else is copied. */
MirValue lb_move_argument(Lb *lb, const MsExpr *e) {
    if (e->kind == MS_E_NAME && lb->facts->res_kind[e->id] == MS_RES_NONE) {
        return la_none_owned(lb, e).v; // `none` where the holder owns what it holds
    }
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

/* A call of the module function `func` of signature `sig`. `receiver` is the expression a method
 * is called on (its first argument, by `var` address when the method changes it), else NULL. */
/* The default of a parameter a call leaves out, lowered where the callee declares it (its names
 * resolve there) inside a scope named for the callee, as a frame called from this line. Only
 * literals and `none` are lowered; any other default refuses the function. */
static MirValue lb_default_argument(Lb *lb, const MsExpr *call, MsSymId callee, const MsExpr *def) {
    const bool plain = def->kind == MS_E_NUMBER || def->kind == MS_E_BOOL || def->kind == MS_E_VOID || def->kind == MS_E_CALL ||
                       def->kind == MS_E_LIST ||
                       (def->kind == MS_E_TEXT && def->u.text.len == 1 && def->u.text.ptr[0].expr == NULL);
    const uint32_t home = lb_view_of(lb, lb->c->syms.module[callee]);
    if (!plain || home == MS_NONE) {
        (void)LB_UNSUPPORTED(lb);
        return MIR_NONE;
    }
    const MsStr name = ms_name(lb->c->names, lb->c->syms.name[callee]);
    const MirScope scope = {.name = mir_name(lb->m, name.ptr, name.len), .file = lb->views[home].file, .parent = lb->b.loc.scope,
                            .call_line = call->pos.line};
    MIR_PUSH(lb->m, lb->b.f.scopes, lb->b.f.nscopes, lb->b.f.cscopes, MirScope, scope);
    const MirLoc outer = lb->b.loc;
    const uint32_t caller = lb_view_enter(lb, home);
    lb->b.loc = (MirLoc){.file = lb->views[home].file, .line = def->pos.line, .col = def->pos.column, .scope = lb->b.f.nscopes};
    const LbVal value = lb_expr(lb, def);
    (void)lb_view_enter(lb, caller);
    lb->b.loc = outer;
    return value.v;
}

/* The values of a call: the arguments of `exprs` in order, then the slots of the `var` arguments. */
typedef struct {
    uint32_t count, offset, ntemps;
    MirValue *args, *temps /* owned arguments */, *slots;
    uint32_t *bindings;
    const MsExpr **exprs;
    bool *by_var;
} LbCallArgs;

static LbCallArgs lb_call_args_new(Lb *lb, uint32_t count, uint32_t offset) {
    const size_t n = (size_t)count + 1;
    return (LbCallArgs){.count = count,
                        .offset = offset,
                        .args = MS_NEW_N(&lb->b.scratch, MirValue, n),
                        .temps = MS_NEW_N(&lb->b.scratch, MirValue, n),
                        .slots = MS_NEW_N(&lb->b.scratch, MirValue, n),
                        .bindings = MS_NEW_N(&lb->b.scratch, uint32_t, n),
                        .exprs = MS_NEW_N(&lb->b.scratch, const MsExpr *, n),
                        .by_var = MS_NEW_N(&lb->b.scratch, bool, n)};
}

/* The expression and passing mode of each argument; a missing one is a parameter with a default. */
static void lb_call_args_bind(LbCallArgs *k, const MsExpr *e, const MsExpr *receiver, bool mutating, const MsTyParam *params) {
    const uint32_t given = e->u.call.args.len;
    for (uint32_t i = 0; i < k->count; i++) {
        const uint32_t at = i - k->offset;
        if (i < k->offset) {
            k->exprs[i] = receiver;
            k->by_var[i] = mutating;
            continue;
        }
        k->exprs[i] = at < given ? e->u.call.args.ptr[at].value : NULL;
        k->by_var[i] = (params[at].flags & MS_PARAM_VAR) != 0;
    }
}

/* Values first, then the slots of the `var` arguments, in argument order each. */
static void lb_call_args_eval(Lb *lb, LbCallArgs *k, const MsExpr *e, uint32_t func, const MsTyParam *params,
                              const MsSymId *callee, const MsFunc *declared) {
    for (uint32_t i = 0; i < k->count && lb->ok; i++) {
        k->slots[i] = MIR_NONE;
        if (k->exprs[i] == NULL) {
            if (declared == NULL) {
                (void)LB_UNSUPPORTED(lb);
                return;
            }
            k->args[i] = lb_default_argument(lb, e, *callee, declared->params.ptr[i - k->offset]->def);
            continue;
        }
        const bool moves = i >= k->offset && (params[i - k->offset].flags & MS_PARAM_MOVE) != 0;
        if (moves || (i < lb->m->funcs[func].nparams && lb->m->funcs[func].params[i].mode == MM_MOVE)) {
            k->args[i] = lb_move_argument(lb, k->exprs[i]);
        } else if (!k->by_var[i]) {
            const LbVal value = lb_expr(lb, k->exprs[i]);
            k->args[i] = value.v;
            if (value.owned) {
                k->temps[k->ntemps++] = value.v; // dropped where the statement ends
            }
        }
    }
    for (uint32_t i = 0; i < k->count && lb->ok; i++) {
        if (k->by_var[i] && k->exprs[i] != NULL) {
            k->args[i] = lb_var_argument(lb, k->exprs[i], &k->bindings[i], &k->slots[i]);
        }
    }
}

/* A borrowing callee over a temporary: the caller owns the result, which is the temporary itself when it came back
 * whole and a copy taken before the temporary is dropped otherwise. The ownership walk numbers the arguments after
 * the receiver, which this does not follow yet. False when the call is not lowered. */
static bool lb_call_owned_result(Lb *lb, LbCallArgs *k, const MsExpr *e, uint8_t how, bool has_receiver, MirValue *result) {
    const uint32_t whole = lb->facts->call_owned_param[e->id];
    const bool is_whole = how == MS_OWNED_WHOLE && whole < e->u.call.args.len;
    if (has_receiver) {
        return false;
    }
    if (!is_whole) {
        *result = lb_copy(lb, *result);
        return true;
    }
    *result = k->args[whole];
    for (uint32_t i = 0; i < k->ntemps; i++) {
        k->temps[i] = k->temps[i] == *result ? MIR_NONE : k->temps[i];
    }
    return true;
}

static LbVal lb_call_declared(Lb *lb, const MsExpr *e, uint32_t func, MsTy sig, const MsExpr *receiver, bool mutating,
                              const MsSymId *callee) {
    const uint32_t offset = receiver != NULL ? 1u : 0u;
    const uint32_t given = e->u.call.args.len;
    const uint32_t nparams = lb->c->tys.nparams[sig];
    const MsFunc *declared = callee == NULL ? NULL : &lb->c->syms.decl[*callee]->u.fn;
    // A call may leave out parameters that have a default, which it evaluates itself.
    const bool defaults = declared != NULL && declared->params.len == nparams && given <= nparams;
    const uint32_t count = (defaults ? nparams : given) + offset;
    if (func == MIR_NONE || (given != nparams && count != nparams + offset) || count != lb->m->funcs[func].nparams) {
        return LB_UNSUPPORTED(lb);
    }
    const MsTyParam *params = ms_ty_params(&lb->c->tys, sig);
    LbCallArgs k = lb_call_args_new(lb, count, offset);
    lb_call_args_bind(&k, e, receiver, mutating, params);
    lb_call_args_eval(lb, &k, e, func, params, callee, declared);
    if (!lb->ok) {
        return LB_FAIL;
    }
    MirValue result = mir_b_call(&lb->b, func, k.args, count);
    const uint8_t how = lb->m->funcs[func].ret_borrowed ? lb->facts->call_owned_borrow[e->id] : MS_OWNED_NONE;
    const bool owns_result = how != MS_OWNED_NONE;
    if (owns_result && !lb_call_owned_result(lb, &k, e, how, receiver != NULL, &result)) {
        return LB_UNSUPPORTED(lb);
    }
    for (uint32_t i = 0; i < k.ntemps; i++) {
        if (k.temps[i] != MIR_NONE) {
            lb_hold_temp(lb, k.temps[i]);
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        if (k.slots[i] != MIR_NONE) {
            const MirTy ty = lb_mir_ty(lb, lb->facts->bindings.ty[k.bindings[i]]);
            mir_b_def_var(&lb->b, lb->var_of[k.bindings[i]], lb_load(lb, k.slots[i], ty));
        }
    }
    const bool borrowed = lb->m->funcs[func].ret_borrowed; // a reference into the arguments
    const MirTy result_ty = mir_b_ty(&lb->b, result);
    return (LbVal){result, owns_result || (lb_owns(lb, result_ty) && !borrowed)}; // else a String result is the caller's
}

LbVal lb_call_func(Lb *lb, const MsExpr *e, uint32_t func, MsTy sig, const MsExpr *receiver, bool mutating) {
    return lb_call_declared(lb, e, func, sig, receiver, mutating, NULL);
}

static LbVal lb_call(Lb *lb, const MsExpr *e) {
    const uint32_t callee = lb->facts->call_callee[e->id];
    const bool builds_record = callee != MS_NONE && lb->c->syms.kind[callee] == MS_SYM_TYPE;
    if ((lb->facts->call_reordered[e->id] && !builds_record) || ms_is_index_store(lb->c->names, e)) {
        return LB_UNSUPPORTED(lb); // arguments are paired with parameters by index below; a store has its own order
    }
    const uint32_t method = lb->facts->call_method[e->id];
    if (method != MS_NONE) {
        return lm_has(lb, method) ? lm_call(lb, e, method) : lb_native_method(lb, e);
    }
    if (callee == MS_NONE && lb->facts->res_kind[e->u.call.callee->id] == MS_RES_CASE) {
        return la_case(lb, e);
    }
    const MsTy dispatch = lb->facts->call_interface[e->id];
    if (dispatch != MS_TY_NONE && ms_ty_kind(&lb->c->tys, lb->facts->call_receiver[e->id]) == MS_K_CONTRACT) {
        return li_call(lb, e);
    }
    if (callee == MS_NONE && dispatch != MS_TY_NONE) {
        return lb_native_method(lb, e); // an operation of a primitive: its runtime function
    }
    if (callee == MS_NONE) {
        return lb_call_value(lb, e);
    }
    if (builds_record) {
        return lr_construct(lb, e);
    }
    if (lx_is_extern(lb, callee)) {
        return lx_call(lb, e, callee);
    }
    return lb_call_declared(lb, e, lb_callee_func(lb, e, callee), lb->c->syms.ty[callee], NULL, false, &callee);
}

LbVal lb_expr_plain(Lb *lb, const MsExpr *e) {
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
    case MS_E_MEMBER: return lb->facts->res_kind[e->id] == MS_RES_CASE ? la_nullary(lb, e) : lr_field(lb, e);
    case MS_E_INDEX:
    case MS_E_APPLY: return lst_index(lb, e);
    case MS_E_LIST: return lst_literal(lb, e);
    case MS_E_MAP: return lm_literal(lb, e);
    case MS_E_VOID: return (LbVal){mir_b_unit(&lb->b), false};
    case MS_E_PROBE: break;
    }
    return LB_UNSUPPORTED(lb);
}

/* `e`, wrapped in `some` where the checker found a payload used for an Optional. */
LbVal lb_expr(Lb *lb, const MsExpr *e) {
    lb_at_expression(lb, e);
    LbVal value = lb_expr_plain(lb, e);
    if (lb->ok && lb->facts->coerce_iface[e->id] != MS_TY_NONE) {
        value = li_box(lb, e, value);
    }
    if (!lb->ok || !lb->facts->some_wrap[e->id]) {
        return value;
    }
    const MirTy payload = mir_b_ty(&lb->b, value.v);
    const bool owns = lb_owns(lb, payload);
    if (value.owned && !owns) {
        return LB_UNSUPPORTED(lb);
    }
    if (owns && !value.owned && lb->b.f.ret_borrowed) {
        return LB_UNSUPPORTED(lb); // the result is a reference into the arguments: a copy would leak, a view has no MIR yet
    }
    if (owns && !value.owned) {
        value = (LbVal){lb_copy(lb, value.v), true}; // an owning Optional holds its own copy of a borrowed payload
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

/* Branches on a String scrutinee by testing the literal arms in order: a short literal with `str.eq_lit`,
 * any other with the runtime's `string_eq`. */
static void lb_dispatch_text(Lb *lb, const MsExpr *e, MirValue scrutinee, const LbArms *arms) {
    const MsArm *const *list = (const MsArm *const *)e->u.match.arms.ptr;
    const uint32_t count = e->u.match.arms.len;
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        if ((int64_t)i == arms->wildcard) {
            continue;
        }
        const MsExpr *path = list[i]->path;
        MirValue same = MIR_NONE;
        const MsStr lit = lb_literal_text(path);
        if (lit.ptr != NULL) {
            const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
            same = mir_b_emit(&lb->b, MOP_StrEqLit, &scrutinee, 1, imm, MIR_BOOL);
        } else {
            const LbVal other = path->kind == MS_E_TEXT ? lb_expr(lb, path) : LB_FAIL;
            const struct MsRtFn *fn = lb_native_function(lb, lb->string_ty, ms_intern_cstr(lb->c->names, "eq"));
            const MirValue args[2] = {scrutinee, other.v};
            const LbVal call = fn == NULL || !lb->ok ? LB_FAIL : lb_native_call(lb, fn, args, 2, MIR_BOOL);
            if (fn == NULL || !lb->ok) {
                (void)LB_UNSUPPORTED(lb);
                return;
            }
            same = call.v;
        }
        const MirBlock next = mir_b_new_block(&lb->b);
        mir_b_br_if(&lb->b, same, arms->blocks[i], NULL, 0, next, NULL, 0);
        mir_b_seal_block(&lb->b, next);
        mir_b_switch_to(&lb->b, next);
    }
    if (lb->ok) {
        mir_b_br(&lb->b, arms->fallback, NULL, 0);
    }
}

/* Branches on the scrutinee once: a `switch` over the literal arms of an Int, a `br_if` over a Bool. */
static void lb_dispatch(Lb *lb, const MsExpr *e, MirValue scrutinee, const LbArms *arms) {
    const MsArm *const *list = (const MsArm *const *)e->u.match.arms.ptr;
    const uint32_t count = e->u.match.arms.len;
    if (mir_b_ty(&lb->b, scrutinee) == MIR_STR) {
        lb_dispatch_text(lb, e, scrutinee, arms);
        return;
    }
    if (mir_ty_data(lb->m, mir_b_ty(&lb->b, scrutinee))->kind == MK_OPT) {
        // The checker numbers an Optional's cases `some` 0 and `none` 1.
        MirBlock when_some = arms->fallback, when_none = arms->fallback;
        for (uint32_t i = 0; i < count; i++) {
            const uint32_t index = lb->facts->arm_case[list[i]->id];
            if (index == 0 && when_some == arms->fallback) {
                when_some = arms->blocks[i];
            } else if (index == 1 && when_none == arms->fallback) {
                when_none = arms->blocks[i];
            }
        }
        const MirValue present = la_test(lb, scrutinee);
        mir_b_br_if(&lb->b, present, when_some, NULL, 0, when_none, NULL, 0);
        return;
    }
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

/* What a match is over: the value, its kind, and whether it is an owned temporary that the arms take
 * apart or drop. */
typedef struct LbSubject {
    MirValue v;
    MirTyKind kind;
    bool temp;
} LbSubject;

/* The binding the arm's `slot`-th payload name introduces, or MS_NONE for `_`. */
static uint32_t lb_arm_binding(const Lb *lb, const MsArm *arm, uint32_t slot) {
    const MsBindings *bindings = &lb->facts->bindings;
    for (uint32_t binding = 0; slot < arm->bindings.len && binding < bindings->count; binding++) {
        if (bindings->decl_node[binding] == arm->id && bindings->name[binding] == arm->bindings.ptr[slot].name) {
            return binding;
        }
    }
    return MS_NONE;
}

/* The payload name of a `x:` arm over an Optional: the value it holds, read in place. */
static void lb_bind_some(Lb *lb, const MsArm *arm, MirValue subject) {
    const uint32_t binding = lb_arm_binding(lb, arm, 0);
    if (binding == MS_NONE) {
        return;
    }
    const MirTy held = mir_ty_data(lb->m, mir_b_ty(&lb->b, subject))->elem;
    lb->value_of[binding] = mir_b_emit(&lb->b, MOP_OptGet, &subject, 1, (MirImm){0}, held);
    lb_name_value(lb, lb->value_of[binding], arm->bindings.ptr[0].name, false);
}

/* Whether the arm names a payload (not `_`). */
static bool lb_arm_names_payload(const Lb *lb, const MsArm *arm) {
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        if (lb_arm_binding(lb, arm, slot) != MS_NONE) {
            return true;
        }
    }
    return false;
}

/* Binds the owned payload `v` to `binding` in the arm's scope, or releases it when the arm names none. */
static void lb_own_payload(Lb *lb, uint32_t binding, MsSym name, MirValue v) {
    lb->value_of[binding] = v;
    lb_name_value(lb, v, name, false);
    if (lb_owns(lb, mir_b_ty(&lb->b, v))) {
        lscope_own(&lb->scopes, v, 0);
        MIR_PUSH(lb->m, lb->parts, lb->nparts, lb->cparts, uint32_t, binding);
    }
}

/* An arm that names a payload of an owned scrutinee takes the parts out of it (`alt.take` each field,
 * then `alt.release` what is left of the box; an Optional is unboxed), as the Rust lowering does. A
 * part the arm does not name is released here, last field first. */
static void lb_take_payloads(Lb *lb, const MsArm *arm, MirValue subject) {
    const MirTyData *data = mir_ty_data(lb->m, mir_b_ty(&lb->b, subject));
    if (data->kind == MK_OPT) {
        const MirValue part = mir_b_emit(&lb->b, MOP_OptUnbox, &subject, 1, (MirImm){0}, data->elem);
        const uint32_t binding = lb_arm_binding(lb, arm, 0);
        if (binding != MS_NONE) {
            lb_own_payload(lb, binding, arm->bindings.ptr[0].name, part);
        } else if (lb_owns(lb, data->elem)) {
            lb_drop(lb, part);
        }
        return;
    }
    const uint32_t index = lb->facts->arm_case[arm->id];
    const MirCaseDef *def = &lb->m->alts[data->id].cases[index];
    if (def->nfields > 32 || arm->bindings.len > def->nfields) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    MirValue parts[32];
    for (uint32_t i = 0; i < def->nfields; i++) {
        const MirImm field = {.tag = MI_ALTFIELD, .a = data->id, .b = index, .c = i};
        parts[i] = mir_b_emit(&lb->b, MOP_AltTake, &subject, 1, field, def->fields[i].ty);
    }
    const uint32_t all = def->nfields == 32 ? UINT32_MAX : (1u << def->nfields) - 1;
    const MirImm mask = {.tag = MI_ALTMASK, .a = data->id, .b = index, .c = all};
    (void)mir_b_emit(&lb->b, MOP_AltRelease, &subject, 1, mask, MIR_NONE);
    bool named[32] = {false};
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        const uint32_t binding = lb_arm_binding(lb, arm, slot);
        if (binding != MS_NONE) {
            lb_own_payload(lb, binding, arm->bindings.ptr[slot].name, parts[slot]);
            named[slot] = true;
        }
    }
    for (uint32_t i = def->nfields; i-- > 0;) {
        if (!named[i] && lb_owns(lb, def->fields[i].ty)) {
            lb_drop(lb, parts[i]);
        }
    }
}

/* The value an arm of a match with an owned result hands to the join: what the arm owns as it is, a
 * text literal as a copy, a name as the value it moves out (its last use) or as a copy of the String it
 * only reads. Anything else is left to the Rust lowering. */
static LbVal lb_arm_owned(Lb *lb, const MsExpr *value_expr, LbVal value) {
    if (value.owned) {
        return value;
    }
    const bool is_string = mir_b_ty(&lb->b, value.v) == MIR_STR;
    if (value_expr->kind == MS_E_TEXT && is_string) {
        return (LbVal){lb_copy(lb, value.v), true};
    }
    if (value_expr->kind != MS_E_NAME) {
        return LB_UNSUPPORTED(lb);
    }
    if (lb->facts->moved_out[value_expr->id]) {
        if (!lb_names_owned(lb, value_expr)) {
            return LB_UNSUPPORTED(lb);
        }
        lscope_disown(&lb->scopes, value.v);
        return (LbVal){value.v, true};
    }
    return is_string ? (LbVal){lb_copy(lb, value.v), true} : LB_UNSUPPORTED(lb);
}

/* One arm: its payload names, statements and final value in a scope of their own, which ends before the join. A
 * Void match discards the value; an owned result takes it over (`lb_arm_owned`). */
static LbVal lb_arm(Lb *lb, const MsArm *arm, const LbSubject *subject, bool void_result, bool owned_result,
                    bool *took) {
    const uint32_t depth = lscope_push(&lb->scopes);
    const bool has_case = lb->facts->arm_case[arm->id] != MS_NONE;
    *took = subject->temp && has_case && lb_arm_names_payload(lb, arm);
    if (*took) {
        lb_take_payloads(lb, arm, subject->v);
    } else if (subject->kind == MK_ALT) {
        lb_bind_arm(lb, arm, subject->v);
    } else if (subject->kind == MK_OPT && lb->facts->arm_case[arm->id] == 0) {
        lb_bind_some(lb, arm, subject->v);
    }
    lb_statements(lb, &arm->body);
    LbVal value = {MIR_NONE, false};
    if (lb->ok && !lb->dead && arm->value != NULL) {
        lb->branching++;
        value = lb_expr(lb, arm->value);
        lb->branching--;
        if (lb->ok && void_result && value.owned) {
            lb_drop(lb, value.v);
        } else if (lb->ok && owned_result) {
            value = lb_arm_owned(lb, arm->value, value);
        }
    }
    if (lb->ok && !lb->dead) {
        lb_own_vars(lb, depth, MIR_NONE);
    }
    while (lb->nvars > 0 && lb->vars[lb->nvars - 1].depth >= depth) {
        lb->nvars--;
    }
    lscope_pop(&lb->scopes, lb->ok && !lb->dead);
    return value;
}


/* `match` over literal arms with one value each. A Bool match is also how `if c: a else: b` is
 * written. Every arm's value joins in one block parameter. */
static LbVal lb_match(Lb *lb, const MsExpr *e) {
    // A match over an interface value tests the concrete type behind it, which lowering does not do yet.
    if (ms_ty_kind(&lb->c->tys, lb->facts->expr_ty[e->u.match.scrutinee->id]) == MS_K_CONTRACT) {
        return LB_UNSUPPORTED(lb);
    }
    const MirTy result_ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    LbVal scrutinee = lb_expr(lb, e->u.match.scrutinee);
    const MirTy scrutinee_ty = lb->ok ? mir_b_ty(&lb->b, scrutinee.v) : MIR_NONE;
    if (lb->ok && !scrutinee.owned && lb->facts->moved_out[e->u.match.scrutinee->id] &&
        lb_names_owned(lb, e->u.match.scrutinee) && lb_owns(lb, scrutinee_ty)) {
        // The match is the owned local's last use: it takes the value over, so the scope stops owning it.
        lscope_disown(&lb->scopes, scrutinee.v);
        scrutinee.owned = true;
    }
    const MirTyKind scrutinee_kind = lb->ok ? mir_ty_data(lb->m, scrutinee_ty)->kind : MK_INT;
    const bool aggregate = lb->ok && scrutinee_kind >= MK_TYPE && scrutinee_kind != MK_ALT && scrutinee_kind != MK_OPT;
    // An owned result is joined as a moved value: each arm hands over a value it owns. A match whose arms
    // are all references (the ownership pass's `borrowed_match`) joins them without copying.
    const bool owned_result = lb->ok && lb_owns(lb, result_ty) && !lb->facts->borrowed_match[e->id];
    const bool void_result = lb->ok && lb_ty(lb, lb->facts->expr_ty[e->id]) == lb->void_ty;
    if (!lb->ok || (result_ty == MIR_NONE && !void_result) || (owned_result && lb->b.f.ret_borrowed) ||
        aggregate || lb_is_fn(lb, result_ty)) {
        return LB_UNSUPPORTED(lb);
    }
    // An owned temporary scrutinee is the match's own: an arm that names a payload takes it apart, and
    // every other arm releases it where the arm ends.
    const bool drops_scrutinee = scrutinee.owned && lb_owns(lb, scrutinee_ty);
    if (drops_scrutinee && scrutinee_kind != MK_ALT && scrutinee_kind != MK_OPT && scrutinee_ty != MIR_STR) {
        return LB_UNSUPPORTED(lb);
    }
    const LbSubject subject = {scrutinee.v, scrutinee_kind, drops_scrutinee};
    const LbArms arms = lb_open_arms(lb, e);
    const MirValue result = void_result ? MIR_NONE
                                        : mir_b_add_block_param(&lb->b, arms.join, result_ty, owned_result ? MM_MOVE : MM_BORROW);
    lb_dispatch(lb, e, scrutinee.v, &arms);
    if (arms.wildcard < 0) {
        mir_b_seal_block(&lb->b, arms.fallback);
        mir_b_switch_to(&lb->b, arms.fallback);
        mir_b_unreachable(&lb->b);
    }
    bool live = false;
    for (uint32_t i = 0; i < e->u.match.arms.len && lb->ok; i++) {
        const MsArm *arm = e->u.match.arms.ptr[i];
        mir_b_seal_block(&lb->b, arms.blocks[i]);
        lb_enter(lb, arms.blocks[i]);
        bool took = false;
        const LbVal value = lb_arm(lb, arm, &subject, void_result, owned_result, &took);
        if (lb->ok && !lb->dead && drops_scrutinee && !took) {
            lb_drop(lb, scrutinee.v);
        }
        if (lb->ok && !lb->dead) {
            mir_b_br(&lb->b, arms.join, void_result ? NULL : &value.v, void_result ? 0 : 1);
            live = true;
        }
    }
    mir_b_seal_block(&lb->b, arms.join);
    lb_enter(lb, arms.join);
    lb->dead = !live;
    return (LbVal){result, owned_result};
}

/* ---- statements ---- */

/* Names `value` for a debugger, as the Rust lowering does: parameters and single-definition locals. */
void lb_name_value(Lb *lb, MirValue value, MsSym name, bool param) {
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
    if (ms_classify(lb->classifier, ty) == MS_CLASS_RESOURCE) { // closed where its scope ends, by the elaborate pass
        if (!lc_bind(lb, s, binding, value)) {
            (void)LB_UNSUPPORTED(lb);
        }
        return;
    }
    if (lb_is_fn(lb, lb_mir_ty(lb, ty)) && (!value.owned || s->u.bind.is_mutable)) {
        (void)LB_UNSUPPORTED(lb); // a function value is owned by the one local made from a lambda or a name
        return;
    }
    if (lb_is_fn(lb, lb_mir_ty(lb, ty))) {
        lscope_own(&lb->scopes, value.v, 0); // the closure is dropped where its scope ends
    }
    const MirTy bound_ty = lb_mir_ty(lb, ty);
    const bool borrows = (lb->facts->bindings.flags[binding] & MS_BIND_BORROWS) != 0; // `y := x`, `y := f(x)` over a borrow
    const bool lent = borrows && !value.owned && !s->u.bind.is_mutable; // a name for a borrowed value: nothing to own or drop
    if (bound_ty != MIR_STR && !lb_is_fn(lb, bound_ty) && lb_owns(lb, bound_ty) && !lent) {
        if (!value.owned) {
            (void)LB_UNSUPPORTED(lb); // a record local is made from a call or a construction
            return;
        }
        if (!s->u.bind.is_mutable) {
            lscope_own(&lb->scopes, value.v, 0); // a `var` is owned at each exit with the value it holds there
        }
    }
    if (ty == lb->string_ty && !borrows) {
        if (!value.owned && s->u.bind.value->kind == MS_E_CALL) {
            (void)LB_UNSUPPORTED(lb); // a call's borrowed result the walk did not mark as a borrowing local
            return;
        }
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
        if (pattern->kind == MS_P_NAME && !borrows) { // a borrowing local is another name for a value that has one
            lb_name_value(lb, value.v, pattern->u.name, false);
        }
    }
}

/* Stores each `var` parameter's current value through its pointer, before the function returns. */
void lb_write_back(Lb *lb) {
    if (lb->closure) {
        return; // a closure has no `var` parameters of its own
    }
    for (uint32_t i = 0; i < lb_slots(&lb->cur); i++) {
        if (lb_slot_mutable(&lb->cur, i)) {
            const uint32_t binding = lb->binding_at[lb_slot_node(&lb->cur, i)];
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

bool lb_var_owned(const Lb *lb, uint32_t binding) {
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
    const MirValue nothing = mir_b_unit(&lb->b);
    const MirValue unit = la_returns_void_result(lb) ? la_ok_of(lb, nothing) : nothing; // `Void!` ends with `ok(void)`
    lb_own_vars(lb, 0, MIR_NONE);
    lscope_exit_to(&lb->scopes, 0);
    lb_write_back(lb);
    lb_depth(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, unit);
    lb->dead = true;
}

/* A borrowed String leaves the function: an owned name moves out as an owned value. */
static LbVal lb_hand_out(Lb *lb, const MsExpr *e, MirValue v) {
    if (e == NULL) {
        (void)LB_UNSUPPORTED(lb); // a bare `return` hands out no expression; a borrowed unit is not made here yet
        return (LbVal){v, true};
    }
    if (e->kind == MS_E_NAME && lb->facts->res_kind[e->id] == MS_RES_NONE) {
        return la_none_owned(lb, e); // `none` where the holder owns what it holds
    }
    if (lb_names_var(lb, e)) {
        return (LbVal){v, true}; // a `var` leaves with its current value: lb_own_vars skips it
    }
    if (lb_names_owned(lb, e)) {
        lscope_disown(&lb->scopes, v);
        return (LbVal){v, true};
    }
    if (e->kind == MS_E_NAME) {
        (void)LB_UNSUPPORTED(lb); // a borrowed parameter handed out as an owned result: left to Rust
        return (LbVal){v, true};
    }
    return (LbVal){lb_copy(lb, v), true}; // a borrowed value that is no local: the caller gets a copy
}

static void lb_return(Lb *lb, const MsStmt *s) {
    const MirValue ok_unit = s->u.expr == NULL ? la_ok_unit(lb) : MIR_NONE;
    if (s->u.expr == NULL && ok_unit == MIR_NONE) {
        lb_return_void(lb);
        return;
    }
    LbVal value = s->u.expr == NULL ? (LbVal){ok_unit, lb_owns(lb, lb->b.f.ret)} : lb_expr(lb, s->u.expr);
    if (!lb->ok) {
        return;
    }
    const MirTy value_ty = mir_b_ty(&lb->b, value.v);
    if (s->u.expr != NULL && lb_owns(lb, value_ty) && !value.owned && !lb->b.f.ret_borrowed) {
        value = lb_hand_out(lb, s->u.expr, value.v);
    }
    const bool leaves_var = !lb->b.f.ret_borrowed && s->u.expr != NULL && lb_names_var(lb, s->u.expr);
    lb_own_temps(lb, lb->stmt_mark);
    lb_own_vars(lb, 0, leaves_var ? value.v : MIR_NONE);
    lscope_exit_to(&lb->scopes, 0);
    lb_write_back(lb);
    lb_depth(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, value.v);
    lb->dead = true;
}


/* Lowers `body` in its own ownership scope, whose end is where control falls out of it. When `taken` is a
 * value, the scope first unboxes the owned Optional `taken` into the payload `pattern` names. Returns the
 * scope's depth. */
static uint32_t lb_scoped_taking(Lb *lb, const MsStmts *body, const MsPattern *pattern, MirValue taken) {
    const uint32_t depth = lscope_push(&lb->scopes);
    if (pattern != NULL) {
        const MirTyData *holder = mir_ty_data(lb->m, mir_b_ty(&lb->b, taken));
        const MirValue part = holder->kind == MK_OPT ? mir_b_emit(&lb->b, MOP_OptUnbox, &taken, 1, (MirImm){0}, holder->elem)
                                                     : la_take_ok(lb, taken); // a Result's Ok value moves out, the rest is released
        lb_own_payload(lb, lb->facts->pattern_binding[pattern->id], pattern->u.name, part);
    }
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

uint32_t lb_scoped(Lb *lb, const MsStmts *body) { return lb_scoped_taking(lb, body, NULL, MIR_NONE); }

/* Starts emitting into `block`, which some live edge reaches. */
void lb_enter(Lb *lb, MirBlock block) {
    mir_b_switch_to(&lb->b, block);
    lb->dead = false;
}

/* Names the payload an `if name := value` unwrapped. */
static void lb_bind_payload(Lb *lb, const MsPattern *pattern, MirValue payload) {
    lb->value_of[lb->facts->pattern_binding[pattern->id]] = payload;
    if (!lb_owns(lb, mir_b_ty(&lb->b, payload))) { // the Rust lowering leaves a payload borrowed from its holder unnamed
        lb_name_value(lb, payload, pattern->u.name, false);
    }
}

/* `if cond: then else: else`; the else branch may be empty. */
static void lb_if(Lb *lb, const MsStmt *s) {
    const uint32_t temps = lb->ntemps;
    LbVal cond = lb_expr(lb, s->u.branch.cond);
    if (!lb->ok) {
        return;
    }
    const MirValue subject = cond.v; // an `if name := value` unwraps it in the then-branch
    const MirTyData *held = mir_ty_data(lb->m, mir_b_ty(&lb->b, subject));
    const bool result_subject = held->kind == MK_ALT && lb->m->alts[held->id].std == MSTD_RESULT;
    if (s->u.branch.binding != NULL && held->kind != MK_OPT && !(result_subject && cond.owned)) {
        (void)LB_UNSUPPORTED(lb); // a borrowed Result keeps its Ok value: read in place, not lowered yet
        return;
    }
    if (s->u.branch.binding != NULL) {
        cond.v = la_test(lb, subject);
    }
    lb_release_temps(lb, temps); // the condition's temporaries end with the condition
    const MirBlock then_block = mir_b_new_block(&lb->b);
    const MirBlock else_block = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    mir_b_br_if(&lb->b, cond.v, then_block, NULL, 0, else_block, NULL, 0);
    mir_b_seal_block(&lb->b, then_block);
    mir_b_seal_block(&lb->b, else_block);
    lb_enter(lb, then_block);
    const MirTy payload_ty = result_subject ? lb->m->alts[held->id].cases[LA_OK].fields[0].ty : held->elem;
    const bool takes = s->u.branch.binding != NULL && cond.owned && (result_subject || lb_owns(lb, payload_ty)); // an owned Result's holder needs a drop whatever its Ok value is
    if (s->u.branch.binding != NULL && !takes) {
        lb_bind_payload(lb, s->u.branch.binding, la_payload(lb, subject, !cond.owned));
    }
    // An owned Optional temporary: the payload moves out into the branch's scope; the else branch drops the holder.
    (void)lb_scoped_taking(lb, &s->u.branch.body, takes ? s->u.branch.binding : NULL, subject);
    const bool then_live = !lb->dead;
    if (then_live) {
        mir_b_br(&lb->b, join, NULL, 0);
    }
    lb_enter(lb, else_block);
    if (takes) {
        lb_drop(lb, subject);
    }
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
MirBlock lb_step_block(Lb *lb, LbLoop *loop) {
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
        (void)LB_UNSUPPORTED(lb);
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
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    if (s->u.assign.member_target) {
        (void)LB_UNSUPPORTED(lb);
        return;
    }
    const MirVar var = lb->var_of[binding];
    const MirValue old = mir_b_use_var(&lb->b, var);
    if (lb_owns(lb, mir_b_ty(&lb->b, old)) && !lb_var_owned(lb, binding)) {
        (void)LB_UNSUPPORTED(lb); // a `var` String parameter lives in the caller's memory: stored back, not dropped here
        return;
    }
    LbVal value = lb_expr(lb, s->u.assign.value);
    if (!lb->ok) {
        return;
    }
    if (lb_owns(lb, mir_b_ty(&lb->b, old))) {
        if (!value.owned && mir_b_ty(&lb->b, old) != MIR_STR) {
            (void)LB_UNSUPPORTED(lb); // a list taken from a name: copy or move is not known yet
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
        (void)LB_UNSUPPORTED(lb);
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
