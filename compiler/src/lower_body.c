/* Lowering of function bodies (the Rust lowering's func.rs, stmt.rs and expr.rs).
 *
 * Handled so far, exactly the checker's first slice (check_body.c) minus what needs ownership:
 * functions whose parameters, locals and result are `Int`, `Float` or `Bool`, with `String` only
 * as a parameter, a literal or a concatenation that is returned; `name := value`, `var name =
 * value`, `return`, literals, names, `not`, unary `-` and `+`, and the binary operators.
 * A function with anything else is skipped: `lb_function` returns false and adds nothing. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"
#include "ms/lower.h"
#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"

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
    MsTy int_ty, float_ty, bool_ty, string_ty;
    /* By binding id: the value a `let` or parameter names, or the variable a `var` is. */
    MirValue *value_of;
    MirVar *var_of;
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE */
    bool ok;              /* false once a construct outside the handled set is met */
} Lb;

#define LB_FAIL ((LbVal){MIR_NONE, false})

static LbVal lb_unsupported(Lb *lb) {
    lb->ok = false;
    return LB_FAIL;
}

static MsTy lb_primitive(const MsCheck *c, const char *name) {
    const MsSymId sym = ms_map_get(&c->primitives, ms_intern_cstr(c->names, name));
    return sym == MS_NONE ? MS_TY_NONE : c->syms.ty[sym];
}

/* The MIR type of a checker type this pass handles, or MIR_NONE. */
static MirTy lb_mir_ty(const Lb *lb, MsTy ty) {
    if (ty == lb->int_ty) {
        return MIR_INT;
    }
    if (ty == lb->float_ty) {
        return MIR_FLOAT;
    }
    if (ty == lb->bool_ty) {
        return MIR_BOOL;
    }
    return ty == lb->string_ty ? MIR_STR : MIR_NONE;
}

static MirLoc lb_loc(MsPos pos) {
    return (MirLoc){.file = 0, .line = pos.line, .col = pos.column, .scope = 0};
}

static void lb_emit_plain(Lb *lb, MirOp op) {
    (void)mir_b_emit(&lb->b, op, NULL, 0, (MirImm){0}, MIR_NONE);
}

/* ---- literals ---- */

static LbVal lb_number(Lb *lb, const MsExpr *e, bool negate) {
    const MsStr text = ms_number_canonical(&lb->m->arena, ms_name(lb->c->names, e->u.sym));
    char *digits = ms_arena_strndup(&lb->m->arena, text.ptr, text.len);
    if (lb->facts->expr_ty[e->id] == lb->float_ty) {
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
    if (e->u.text.len != 1 || e->u.text.ptr[0].expr != NULL) {
        return lb_unsupported(lb);
    }
    const MsStr lit = e->u.text.ptr[0].lit;
    MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
    return (LbVal){mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false};
}

/* ---- names ---- */

static LbVal lb_name(Lb *lb, const MsExpr *e) {
    const MsFacts *facts = lb->facts;
    if (facts->res_kind[e->id] != MS_RES_BINDING) {
        return lb_unsupported(lb);
    }
    const uint32_t binding = facts->res_ref[e->id];
    if (lb->var_of[binding] != MIR_NONE) {
        return (LbVal){mir_b_use_var(&lb->b, lb->var_of[binding]), false};
    }
    return (LbVal){lb->value_of[binding], false};
}

/* ---- operators ---- */

static LbVal lb_expr(Lb *lb, const MsExpr *e);

static LbVal lb_unary(Lb *lb, const MsExpr *e) {
    const MsExpr *operand = e->u.bin.left;
    const MsUnaryOp op = (MsUnaryOp)e->op;
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
    const LbVal right = lb_expr(lb, e->u.bin.right);
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
    if (left.owned || right.owned) {
        return lb_unsupported(lb); // a temporary to drop after the call
    }
    const MirValue args[2] = {left.v, right.v};
    return (LbVal){mir_b_call_rt(&lb->b, lb_string_concat(lb), args, 2), true};
}

static LbVal lb_compare(Lb *lb, MsBinaryOp op, LbVal left, LbVal right) {
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    const MirImm cc = {.tag = MI_CC, .a = (uint32_t)lb_cc(op)};
    const MirValue args[2] = {left.v, right.v};
    if (ty == MIR_STR) {
        return lb_unsupported(lb);
    }
    const MirOp mir_op = ty == MIR_FLOAT ? MOP_FCmp : MOP_ICmp;
    MirValue result = mir_b_emit(&lb->b, mir_op, args, 2, cc, MIR_BOOL);
    if (op == MS_B_NE) {
        result = mir_b_emit(&lb->b, MOP_Not, &result, 1, (MirImm){0}, MIR_BOOL);
    }
    return (LbVal){result, false};
}

static LbVal lb_binary(Lb *lb, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    if (op == MS_B_AND || op == MS_B_OR) {
        return lb_short_circuit(lb, e);
    }
    const LbVal left = lb_expr(lb, e->u.bin.left);
    const LbVal right = lb->ok ? lb_expr(lb, e->u.bin.right) : LB_FAIL;
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirTy ty = mir_b_ty(&lb->b, left.v);
    if (op == MS_B_ADD && ty == MIR_STR) {
        return lb_concat(lb, left, right);
    }
    const MirOp arithmetic = lb_arithmetic_op(op, ty);
    if (arithmetic == MOP_COUNT) {
        return lb_compare(lb, op, left, right);
    }
    return (LbVal){mir_b_binop(&lb->b, arithmetic, left.v, right.v), false};
}

static LbVal lb_expr(Lb *lb, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: return lb_number(lb, e, false);
    case MS_E_BOOL: return (LbVal){mir_b_bconst(&lb->b, e->u.flag), false};
    case MS_E_TEXT: return lb_text(lb, e);
    case MS_E_NAME: return lb_name(lb, e);
    case MS_E_UNARY: return lb_unary(lb, e);
    case MS_E_BINARY: return lb_binary(lb, e);
    case MS_E_VOID:
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH: break;
    }
    return lb_unsupported(lb);
}

/* ---- statements ---- */

static void lb_bind(Lb *lb, const MsStmt *s) {
    const MsPattern *pattern = s->u.bind.pattern;
    const uint32_t binding = lb->facts->pattern_binding[pattern->id];
    const MsTy ty = lb->facts->bindings.ty[binding];
    if (ty == lb->string_ty) {
        lb->ok = false; // a String local owns its value: scopes come with ownership
        return;
    }
    const LbVal value = lb_expr(lb, s->u.bind.value);
    if (!lb->ok) {
        return;
    }
    if (s->u.bind.is_mutable) {
        lb->var_of[binding] = mir_b_declare_var(&lb->b, lb_mir_ty(lb, ty), MM_BORROW);
        mir_b_def_var(&lb->b, lb->var_of[binding], value.v);
    } else {
        lb->value_of[binding] = value.v;
    }
}

static void lb_return(Lb *lb, const MsStmt *s) {
    if (s->u.expr == NULL) {
        lb->ok = false;
        return;
    }
    const LbVal value = lb_expr(lb, s->u.expr);
    if (!lb->ok) {
        return;
    }
    if (mir_b_ty(&lb->b, value.v) == MIR_STR && !value.owned) {
        lb->ok = false; // handing out a borrowed String copies it
        return;
    }
    lb_emit_plain(lb, MOP_DepthLeave);
    mir_b_ret(&lb->b, value.v);
}

static void lb_statement(Lb *lb, const MsStmt *s) {
    mir_b_set_loc(&lb->b, lb_loc(s->pos));
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND: lb_bind(lb, s); return;
    case MS_S_RETURN: lb_return(lb, s); return;
    case MS_S_ASSIGN:
    case MS_S_CALL:
    case MS_S_BREAK:
    case MS_S_CONTINUE:
    case MS_S_IF:
    case MS_S_WHILE:
    case MS_S_FOR: break;
    }
    lb->ok = false;
}

/* ---- functions ---- */

/* Starts the function and binds its parameters; false when a parameter or the result is not a
 * type this pass handles. */
static bool lb_begin(Lb *lb, const MsDecl *d, MsSymId sym) {
    const MsFunc *fn = &d->u.fn;
    const MsTy sig = lb->c->syms.ty[sym];
    const MirTy ret = lb_mir_ty(lb, lb->c->tys.result[sig]);
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, fn->params.len + 1);
    const MsTyParam *sig_params = ms_ty_params(&lb->c->tys, sig);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MirTy ty = lb_mir_ty(lb, sig_params[i].ty);
        if (ty == MIR_NONE) {
            return false;
        }
        params[i] = (MirParam){ty, MM_BORROW};
    }
    if (ret == MIR_NONE) {
        return false;
    }
    const MsStr name = ms_name(lb->c->names, fn->name);
    mir_b_init(&lb->b, lb->m, mir_name(lb->m, name.ptr, name.len), params, fn->params.len, ret);
    lb->b.f.loc = lb_loc(d->pos);
    MirValue *values = MS_NEW_N(&lb->m->arena, MirValue, fn->params.len + 1);
    mir_b_params(&lb->b, values, fn->params.len);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        lb->value_of[lb->binding_at[fn->params.ptr[i]->id]] = values[i];
    }
    lb_emit_plain(lb, MOP_DepthEnter);
    return true;
}

/* Lowers one checked function into the module; false (nothing added) when it is not handled. */
static bool lb_function(Lb *lb, const MsDecl *d, MsSymId sym) {
    lb->ok = lb_begin(lb, d, sym);
    if (!lb->ok) {
        return false;
    }
    const MsStmts *body = &d->u.fn.body;
    for (uint32_t i = 0; i < body->len && lb->ok; i++) {
        lb_statement(lb, body->ptr[i]);
    }
    uint32_t id = 0;
    if (!lb->ok) {
        MirFunc discarded;
        const bool built = mir_b_into_func(&lb->b, &discarded); // frees the builder's scratch tables
        (void)built;
        return false;
    }
    mir_func_compact_blocks(&lb->b.f); // unreachable blocks go; the rest in reverse post-order
    const MsStr name = ms_name(lb->c->names, d->u.fn.name);
    if (name.len == 4 && memcmp(name.ptr, "main", 4) == 0) {
        lb->b.f.linkage = ML_EXPORT;
    }
    return mir_b_finish(&lb->b, &id);
}

static void lb_index_bindings(Lb *lb, MsArena *arena) {
    const MsBindings *bindings = &lb->facts->bindings;
    const size_t nodes = (size_t)lb->facts->node_count + 1;
    lb->binding_at = MS_NEW_N(arena, uint32_t, nodes);
    memset(lb->binding_at, 0xff, nodes * sizeof *lb->binding_at);
    for (uint32_t i = 0; i < bindings->count; i++) {
        lb->binding_at[bindings->decl_node[i]] = i;
    }
    lb->value_of = MS_NEW_N(arena, MirValue, bindings->count + 1);
    lb->var_of = MS_NEW_N(arena, MirVar, bindings->count + 1);
    memset(lb->var_of, 0xff, (bindings->count + 1) * sizeof *lb->var_of);
    memset(lb->value_of, 0xff, (bindings->count + 1) * sizeof *lb->value_of);
}

uint32_t ms_lower_module(const MsCheck *c, MsModId module, MirModule *out) {
    const MsModuleRow *row = &c->mods[module];
    const MsFacts *facts = row->facts;
    if (facts == NULL || facts->body_checked == NULL) {
        return 0;
    }
    Lb lb = {.c = c,
             .facts = facts,
             .m = out,
             .int_ty = lb_primitive(c, "Int"),
             .float_ty = lb_primitive(c, "Float"),
             .bool_ty = lb_primitive(c, "Bool"),
             .string_ty = lb_primitive(c, "String")};
    lb_index_bindings(&lb, &out->arena);
    uint32_t lowered = 0;
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool checked = d->kind == MS_D_FN && facts->body_checked[d->id];
        const MsSymId sym = checked ? ms_decl_own_symbol(c, module, d) : MS_NONE;
        lowered += sym != MS_NONE && lb_function(&lb, d, sym) ? 1 : 0;
    }
    return lowered;
}
