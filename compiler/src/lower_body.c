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

/* The loop being lowered: where `continue` and `break` go. Lives on the lowering's stack. */
typedef struct LbLoop {
    MirBlock header, exit;
    struct LbLoop *outer;
    bool broke; /* a `break` branches to `exit` */
} LbLoop;

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
    uint32_t *func_of;    /* by symbol id: the module function a call reaches, or MIR_NONE */
    uint32_t *binding_at; /* by node id: the binding that node introduces, or MS_NONE */
    const MsStmt *stmt;   /* the statement being lowered: every instruction in it reports its position */
    LbLoop *loop;         /* the innermost loop around the statement, or NULL */
    bool dead;            /* control cannot reach the current position */
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
static LbVal lb_match(Lb *lb, const MsExpr *e);

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

/* A call of a module function the checker resolved; MIR_NONE-valued `func_of` means the callee
 * is not lowered, so neither is the caller. */
static LbVal lb_call(Lb *lb, const MsExpr *e) {
    const uint32_t callee = lb->facts->call_callee[e->id];
    const uint32_t func = callee == MS_NONE ? MIR_NONE : lb->func_of[callee];
    if (func == MIR_NONE) {
        return lb_unsupported(lb);
    }
    const uint32_t count = e->u.call.args.len;
    MirValue *args = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    for (uint32_t i = 0; i < count; i++) {
        const LbVal arg = lb_expr(lb, e->u.call.args.ptr[i].value);
        if (!lb->ok || arg.owned) {
            return lb_unsupported(lb); // an owned temporary needs a drop after the call
        }
        args[i] = arg.v;
    }
    return (LbVal){mir_b_call(&lb->b, func, args, count), false};
}

static LbVal lb_expr(Lb *lb, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: return lb_number(lb, e, false);
    case MS_E_BOOL: return (LbVal){mir_b_bconst(&lb->b, e->u.flag), false};
    case MS_E_TEXT: return lb_text(lb, e);
    case MS_E_NAME: return lb_name(lb, e);
    case MS_E_UNARY: return lb_unary(lb, e);
    case MS_E_BINARY: return lb_binary(lb, e);
    case MS_E_MATCH: return lb_match(lb, e);
    case MS_E_CALL: return lb_call(lb, e);
    case MS_E_VOID:
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA: break;
    }
    return lb_unsupported(lb);
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

/* `match` over literal arms with one value each. A Bool match is also how `if c: a else: b` is
 * written. Every arm's value joins in one block parameter. */
static LbVal lb_match(Lb *lb, const MsExpr *e) {
    const MirTy result_ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    const LbVal scrutinee = lb_expr(lb, e->u.match.scrutinee);
    const MirTy scrutinee_ty = lb->ok ? mir_b_ty(&lb->b, scrutinee.v) : MIR_NONE;
    if (!lb->ok || result_ty == MIR_NONE || result_ty == MIR_STR || scrutinee_ty == MIR_STR) {
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
        const LbVal value = lb_expr(lb, e->u.match.arms.ptr[i]->value);
        if (lb->ok) {
            mir_b_br(&lb->b, arms.join, &value.v, 1);
        }
    }
    mir_b_seal_block(&lb->b, arms.join);
    mir_b_switch_to(&lb->b, arms.join);
    return (LbVal){result, false};
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
    lb->dead = true;
}

static void lb_statements(Lb *lb, const MsStmts *body);

/* Starts emitting into `block`, which some live edge reaches. */
static void lb_enter(Lb *lb, MirBlock block) {
    mir_b_switch_to(&lb->b, block);
    lb->dead = false;
}

/* `if cond: then else: else`; the else branch may be empty. */
static void lb_if(Lb *lb, const MsStmt *s) {
    const LbVal cond = lb_expr(lb, s->u.branch.cond);
    if (!lb->ok) {
        return;
    }
    const MirBlock then_block = mir_b_new_block(&lb->b);
    const MirBlock else_block = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    mir_b_br_if(&lb->b, cond.v, then_block, NULL, 0, else_block, NULL, 0);
    mir_b_seal_block(&lb->b, then_block);
    mir_b_seal_block(&lb->b, else_block);
    lb_enter(lb, then_block);
    lb_statements(lb, &s->u.branch.body);
    const bool then_live = !lb->dead;
    if (then_live) {
        mir_b_br(&lb->b, join, NULL, 0);
    }
    lb_enter(lb, else_block);
    lb_statements(lb, &s->u.branch.else_body);
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
    LbLoop here = {header, exit, lb->loop, false};
    lb->loop = &here;
    lb_statements(lb, &s->u.loop.body);
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
    mir_b_br(&lb->b, s->kind == MS_S_BREAK ? loop->exit : loop->header, NULL, 0);
    lb->dead = true;
}

/* `name = value` writes the `var` the checker resolved the statement to. */
static void lb_assign(Lb *lb, const MsStmt *s) {
    const uint32_t binding = lb->facts->assign_binding[s->id];
    if (binding == MS_NONE || lb->var_of[binding] == MIR_NONE) {
        lb->ok = false;
        return;
    }
    const LbVal value = lb_expr(lb, s->u.assign.value);
    if (lb->ok) {
        mir_b_def_var(&lb->b, lb->var_of[binding], value.v);
    }
}

/* Lowers a statement; every instruction in it reports the statement's own position, and the
 * enclosing statement's position comes back once it ends. */
static void lb_statement(Lb *lb, const MsStmt *s) {
    const MsStmt *outer = lb->stmt;
    lb->stmt = s;
    mir_b_set_loc(&lb->b, lb_loc(s->pos));
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND: lb_bind(lb, s); break;
    case MS_S_RETURN: lb_return(lb, s); break;
    case MS_S_IF: lb_if(lb, s); break;
    case MS_S_WHILE: lb_while(lb, s); break;
    case MS_S_ASSIGN: lb_assign(lb, s); break;
    case MS_S_BREAK:
    case MS_S_CONTINUE: lb_jump(lb, s); break;
    case MS_S_CALL:
    case MS_S_FOR: lb->ok = false; break;
    }
    lb->stmt = outer;
    if (outer != NULL) {
        mir_b_set_loc(&lb->b, lb_loc(outer->pos));
    }
}

static void lb_statements(Lb *lb, const MsStmts *body) {
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
    *ret = lb_mir_ty(lb, lb->c->tys.result[sig]);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MirTy ty = lb_mir_ty(lb, sig_params[i].ty);
        if (ty == MIR_NONE) {
            return false;
        }
        params[i] = (MirParam){ty, MM_BORROW};
    }
    return *ret != MIR_NONE;
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

/* Lowers one checked function over its stub `slot` in the module; false when it is not handled. */
static bool lb_function(Lb *lb, const MsDecl *d, MsSymId sym, uint32_t slot) {
    lb->ok = lb_begin(lb, d, sym);
    if (!lb->ok) {
        return false;
    }
    lb->dead = false;
    lb->loop = NULL;
    lb->stmt = NULL;
    lb_statements(lb, &d->u.fn.body);
    lb->ok = lb->ok && lb->dead; // a path that ends without `return` is a Void function's
    MirFunc f = {0};
    if (lb->ok) {
        mir_func_compact_blocks(&lb->b.f); // unreachable blocks go; the rest in reverse post-order
        const MsStr name = ms_name(lb->c->names, d->u.fn.name);
        if (name.len == 4 && memcmp(name.ptr, "main", 4) == 0) {
            lb->b.f.linkage = ML_EXPORT;
        }
    }
    // Finishing also frees the builder's scratch tables, which a failed function needs too.
    const bool built = mir_b_into_func(&lb->b, &f);
    if (lb->ok && built) {
        lb->m->funcs[slot] = f;
    }
    return lb->ok && built;
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
    mir_func_init(lb->m, &stub, mir_name(lb->m, name.ptr, name.len), params, fn->params.len, ret);
    return mir_add_func(lb->m, &stub);
}

/* One pass over the module's checked functions: stub each one not in `failed`, then lower them.
 * A function that does not lower is marked in `failed`; true when any new one was. */
static bool lb_pass(Lb *lb, MsModId module, bool *failed, uint32_t *lowered) {
    const MsModuleRow *row = &lb->c->mods[module];
    const uint32_t ndecls = row->syntax->ndecls;
    memset(lb->func_of, 0xff, (size_t)lb->c->syms.count * sizeof *lb->func_of);
    MsSymId *syms = MS_NEW_N(&lb->m->arena, MsSymId, (size_t)ndecls + 1);
    for (uint32_t i = 0; i < ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool checked = d->kind == MS_D_FN && lb->facts->body_checked[d->id] && !failed[i];
        syms[i] = checked ? ms_decl_own_symbol(lb->c, module, d) : MS_NONE;
        if (syms[i] != MS_NONE) {
            lb->func_of[syms[i]] = lb_add_stub(lb, d, syms[i]);
        }
    }
    bool changed = false;
    *lowered = 0;
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
    return changed;
}

/* A failed function leaves a stub, and calls to it were lowered against it, so the pass repeats
 * without it (its callers then fail too) until a pass loses nothing. That is at most one pass per
 * function; programs lose a function or two. */
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
    bool *failed = calloc((size_t)row->syntax->ndecls + 1, sizeof *failed);
    lb.func_of = calloc((size_t)c->syms.count + 1, sizeof *lb.func_of);
    uint32_t lowered = 0;
    while (failed != NULL && lb.func_of != NULL) {
        mir_module_free(out);
        mir_module_init(out);
        lb_index_bindings(&lb, &out->arena);
        if (!lb_pass(&lb, module, failed, &lowered)) {
            break;
        }
    }
    free(lb.func_of);
    free(failed);
    return lowered;
}
