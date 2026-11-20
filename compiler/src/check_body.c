/* Function bodies: the types of expressions and the bindings of names (the Rust checker's
 * stmts.rs and exprs.rs).
 *
 * The pass grows by constructs. A function is checked only when every statement and expression in
 * it is one the pass handles, and every one of them is accepted without a diagnostic; otherwise
 * the function is left unchecked and no fact of it remains. That keeps the differential against the
 * Rust checker (compiler/tests/check-diff.sh) exact for what the pass claims: it compares the
 * facts of the checked functions and requires the Rust checker to report nothing inside them.
 *
 * Handled so far: functions without type parameters whose parameters, locals and result are
 * `Int`, `Float`, `Bool` or `String` (result also `Void`); `name := value`, `var name = value`
 * with an optional primitive annotation; `return`; number, bool, void and text literals, names
 * of locals, `not`, unary `-` and `+`, and the binary operators over operands of one primitive
 * type. */
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"

typedef struct Body {
    MsCheck *c;
    MsModId module;
    MsFacts *facts;
    MsLiteralFacts *literals;
    MsTy int_ty, float_ty, bool_ty, string_ty, void_ty;
    MsTy result;
    uint32_t first_binding; /* the bindings from here on belong to the function being checked */
    MsBuf written;          /* expression ids whose type this function wrote, to undo them */
    bool supported;         /* false once a construct outside the handled set is met */
} Body;

static MsTy body_primitive(const MsCheck *c, const char *name) {
    const MsSymId sym = ms_map_get(&c->primitives, ms_intern_cstr(c->names, name));
    return sym == MS_NONE ? MS_TY_NONE : c->syms.ty[sym];
}

static bool body_is_value_type(const Body *b, MsTy ty) {
    return ty != MS_TY_NONE && (ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty || ty == b->string_ty);
}

static bool body_is_numeric(const Body *b, MsTy ty) {
    return ty == b->int_ty || ty == b->float_ty;
}

/* Gives up on the function; the caller returns `<invalid>` (MS_TY_NONE) up the tree. */
static MsTy body_unsupported(Body *b) {
    b->supported = false;
    return MS_TY_NONE;
}

static bool body_text_is(const Body *b, MsSym name, const char *text) {
    const MsStr s = ms_name(b->c->names, name);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

static MsTy body_record(Body *b, uint32_t node, MsTy ty) {
    b->facts->expr_ty[node] = ty;
    MS_VEC_PUSH(b->written, uint32_t, node);
    return ty;
}

/* ---- bindings ---- */

static uint32_t body_find_binding(const Body *b, MsSym name) {
    const MsBindings *bindings = &b->facts->bindings;
    for (uint32_t i = bindings->count; i > b->first_binding; i--) {
        if (bindings->name[i - 1] == name) {
            return i - 1;
        }
    }
    return MS_NONE;
}

/* Binds a name in the function's one scope. A name already bound there would be a diagnostic. */
static uint32_t body_bind(Body *b, MsSym name, MsTy ty, uint32_t node, uint8_t flags, MsBindRole role) {
    if (!body_text_is(b, name, "_") && body_find_binding(b, name) != MS_NONE) {
        (void)body_unsupported(b);
        return MS_NONE;
    }
    MsBindings *bindings = &b->facts->bindings;
    const uint32_t id = bindings->count++;
    bindings->name[id] = name;
    bindings->ty[id] = ty;
    bindings->decl_node[id] = node;
    bindings->callable[id] = 0;
    bindings->flags[id] = flags;
    bindings->role[id] = (uint8_t)role;
    return id;
}

/* ---- expressions ---- */

static MsTy body_expr(Body *b, const MsExpr *e, MsTy expected);

static MsTy body_number(Body *b, const MsExpr *e) {
    MsCheck *c = b->c;
    const MsStr text = ms_number_canonical(&c->arena, ms_name(c->names, e->u.sym));
    if (ms_number_is_decimal(text)) {
        return body_unsupported(b);
    }
    char *digits = ms_arena_strndup(&c->arena, text.ptr, text.len);
    char *end = NULL;
    errno = 0;
    if (ms_number_is_fractional(text)) {
        const double value = strtod(digits, &end);
        return *end != '\0' || isinf(value) ? body_unsupported(b) : b->float_ty;
    }
    (void)strtoll(digits, &end, 10);
    return *end != '\0' || errno != 0 ? body_unsupported(b) : b->int_ty;
}

static MsTy body_text(Body *b, const MsExpr *e) {
    for (uint32_t i = 0; i < e->u.text.len; i++) {
        const MsExpr *part = e->u.text.ptr[i].expr;
        if (part != NULL && body_expr(b, part, MS_TY_NONE) == MS_TY_NONE) {
            return MS_TY_NONE;
        }
    }
    return b->string_ty;
}

static MsTy body_name(Body *b, const MsExpr *e) {
    const uint32_t binding = body_find_binding(b, e->u.sym);
    if (binding == MS_NONE || body_text_is(b, e->u.sym, "none")) {
        return body_unsupported(b);
    }
    b->facts->res_kind[e->id] = MS_RES_BINDING;
    b->facts->res_ref[e->id] = binding;
    b->facts->bindings.flags[binding] |= MS_BIND_READ;
    return b->facts->bindings.ty[binding];
}

static MsTy body_unary(Body *b, const MsExpr *e) {
    const MsExpr *operand = e->u.bin.left;
    const MsUnaryOp op = (MsUnaryOp)e->op;
    if (op == MS_U_TRY) {
        return body_unsupported(b);
    }
    if (op == MS_U_NEG && operand->kind == MS_E_NUMBER) {
        // A negated literal is typed as the literal; -9223372036854775808 is Int's own case.
        const MsStr text = ms_number_canonical(&b->c->arena, ms_name(b->c->names, operand->u.sym));
        if (text.len == 19 && memcmp(text.ptr, "9223372036854775808", 19) == 0) {
            return body_unsupported(b);
        }
        const MsTy literal = body_number(b, operand);
        return literal == MS_TY_NONE ? literal : body_record(b, operand->id, literal);
    }
    const MsTy operand_ty = body_expr(b, operand, MS_TY_NONE);
    if (operand_ty == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    if (op == MS_U_NOT) {
        return operand_ty == b->bool_ty ? b->bool_ty : body_unsupported(b);
    }
    return body_is_numeric(b, operand_ty) ? operand_ty : body_unsupported(b);
}

static bool body_is_ordering(MsBinaryOp op) {
    return op == MS_B_LT || op == MS_B_GT || op == MS_B_LE || op == MS_B_GE;
}

/* Integer arithmetic over constants that always faults is a diagnostic. */
static bool body_constant_fault(Body *b, const MsExpr *e) {
    const MsStr fault = ms_constant_arithmetic_fault(&b->c->arena, b->literals, (MsBinaryOp)e->op, e->u.bin.left,
                                                     e->u.bin.right, "Int", INT64_MIN, INT64_MAX);
    return fault.len != 0;
}

static MsTy body_binary(Body *b, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    const MsTy left = body_expr(b, e->u.bin.left, MS_TY_NONE);
    const MsTy right = left == MS_TY_NONE ? MS_TY_NONE : body_expr(b, e->u.bin.right, MS_TY_NONE);
    if (right == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    if (op == MS_B_AND || op == MS_B_OR) {
        return left == b->bool_ty && right == b->bool_ty ? b->bool_ty : body_unsupported(b);
    }
    if (left != right || !body_is_value_type(b, left)) {
        return body_unsupported(b);
    }
    if (op == MS_B_EQ || op == MS_B_NE) {
        return b->bool_ty;
    }
    if (body_is_ordering(op)) {
        return left == b->bool_ty ? body_unsupported(b) : b->bool_ty;
    }
    if (left == b->string_ty) {
        return op == MS_B_ADD ? left : body_unsupported(b);
    }
    const bool numeric = body_is_numeric(b, left);
    const bool remainder_of_float = op == MS_B_REM && left != b->int_ty;
    if (!numeric || remainder_of_float || (left == b->int_ty && body_constant_fault(b, e))) {
        return body_unsupported(b);
    }
    return left;
}

/* The type of `e` where `expected` is the type the context wants, or MS_TY_NONE for no
 * expectation. A type that is not the expected one is a diagnostic. */
static MsTy body_expr(Body *b, const MsExpr *e, MsTy expected) {
    MsTy ty = MS_TY_NONE;
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: ty = body_number(b, e); break;
    case MS_E_BOOL: ty = b->bool_ty; break;
    case MS_E_VOID: ty = b->void_ty; break;
    case MS_E_TEXT: ty = body_text(b, e); break;
    case MS_E_NAME: ty = body_name(b, e); break;
    case MS_E_UNARY: ty = body_unary(b, e); break;
    case MS_E_BINARY: ty = body_binary(b, e); break;
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH: return body_unsupported(b);
    }
    if (ty == MS_TY_NONE) {
        return ty;
    }
    if (expected != MS_TY_NONE && ty != expected) {
        return body_unsupported(b);
    }
    return body_record(b, e->id, ty);
}

/* ---- statements ---- */

/* The primitive type a written annotation names, or MS_TY_NONE. */
static MsTy body_annotation(Body *b, const MsTypeRef *t) {
    if (t->kind != MS_TYPE_NAMED || t->args.len != 0) {
        return body_unsupported(b);
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
    const MsTy ty = sym == MS_NONE ? MS_TY_NONE : b->c->syms.ty[sym];
    if (!body_is_value_type(b, ty) || b->c->syms.decl[sym] != NULL) {
        return body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

static void body_bind_statement(Body *b, const MsStmt *s) {
    const MsPattern *pattern = s->u.bind.pattern;
    if (pattern->kind != MS_P_NAME || s->u.bind.has_group) {
        (void)body_unsupported(b);
        return;
    }
    const MsTy expected = s->u.bind.ty == NULL ? MS_TY_NONE : body_annotation(b, s->u.bind.ty);
    if (!b->supported) {
        return;
    }
    const MsTy value = body_expr(b, s->u.bind.value, expected);
    if (value == MS_TY_NONE || !body_is_value_type(b, value)) {
        (void)body_unsupported(b);
        return;
    }
    const uint8_t flags = s->u.bind.is_mutable ? MS_BIND_MUTABLE : 0;
    const MsBindRole role = s->u.bind.is_mutable ? MS_ROLE_VAR : MS_ROLE_LET;
    const uint32_t binding = body_bind(b, pattern->u.name, value, pattern->id, flags, role);
    if (binding != MS_NONE) {
        b->facts->pattern_binding[pattern->id] = binding;
    }
}

static void body_return_statement(Body *b, const MsStmt *s) {
    const MsExpr *value = s->u.expr;
    if (value == NULL) {
        b->supported = b->supported && b->result == b->void_ty;
        return;
    }
    (void)body_expr(b, value, b->result);
}

/* Checks the statements in order. A statement after a `return` is left to the Rust checker. */
static void body_statements(Body *b, const MsStmts *body) {
    bool reachable = true;
    for (uint32_t i = 0; i < body->len && b->supported; i++) {
        const MsStmt *s = body->ptr[i];
        if (!reachable) {
            (void)body_unsupported(b);
            return;
        }
        switch ((MsStmtKind)s->kind) {
        case MS_S_BIND: body_bind_statement(b, s); break;
        case MS_S_RETURN:
            body_return_statement(b, s);
            reachable = false;
            break;
        case MS_S_ASSIGN:
        case MS_S_CALL:
        case MS_S_BREAK:
        case MS_S_CONTINUE:
        case MS_S_IF:
        case MS_S_WHILE:
        case MS_S_FOR: (void)body_unsupported(b); break;
        }
    }
    // A local nothing reads, unless named with a leading `_`, is a diagnostic.
    const MsBindings *bindings = &b->facts->bindings;
    for (uint32_t i = b->first_binding; b->supported && i < bindings->count; i++) {
        const bool local = bindings->role[i] == MS_ROLE_LET || bindings->role[i] == MS_ROLE_VAR;
        const MsStr name = ms_name(b->c->names, bindings->name[i]);
        const bool ignored = name.len != 0 && name.ptr[0] == '_';
        b->supported = !local || ignored || (bindings->flags[i] & MS_BIND_READ) != 0;
    }
    // A function that returns a value must end every path with a `return`.
    if (b->supported && reachable && b->result != b->void_ty) {
        (void)body_unsupported(b);
    }
}

/* ---- functions ---- */

static void body_undo(Body *b, uint32_t first_binding, size_t written_start) {
    const uint32_t *ids = ms_buf_items(&b->written);
    for (size_t i = written_start; i < MS_VEC_LEN(b->written, uint32_t); i++) {
        b->facts->expr_ty[ids[i]] = MS_TY_NONE;
        b->facts->res_kind[ids[i]] = MS_RES_NONE;
        b->facts->res_ref[ids[i]] = MS_NONE;
    }
    b->written.len = written_start * sizeof(uint32_t);
    b->facts->bindings.count = first_binding;
}

static bool body_signature_supported(const Body *b, const MsFunc *fn, MsTy sig) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != fn->params.len || fn->type_params.len != 0) {
        return false;
    }
    const MsTy result = tys->result[sig];
    if (!body_is_value_type(b, result) && result != b->void_ty) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MsParam *p = fn->params.ptr[i];
        if (p->def != NULL || p->is_mutable || p->moving || !body_is_value_type(b, params[i].ty)) {
            return false;
        }
    }
    return true;
}

static void body_check_function(Body *b, const MsDecl *d, MsSymId sym) {
    const MsFunc *fn = &d->u.fn;
    const MsTy sig = b->c->syms.ty[sym];
    if (fn->external || b->c->syms.nvars[sym] != 0 || !body_signature_supported(b, fn, sig)) {
        return;
    }
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    b->first_binding = first_binding;
    b->supported = true;
    b->result = b->c->tys.result[sig];
    const MsTyParam *params = ms_ty_params(&b->c->tys, sig);
    for (uint32_t i = 0; i < fn->params.len && b->supported; i++) {
        (void)body_bind(b, params[i].name, params[i].ty, fn->params.ptr[i]->id, 0, MS_ROLE_PARAM);
    }
    if (b->supported) {
        body_statements(b, &fn->body);
    }
    if (b->supported) {
        b->facts->body_checked[d->id] = true;
    } else {
        body_undo(b, first_binding, written_start);
    }
}

static void body_allocate(Body *b, MsFacts *facts) {
    MsArena *arena = &b->c->arena;
    const size_t nodes = (size_t)facts->node_count + 1;
    facts->expr_ty = MS_NEW_N(arena, MsTy, nodes);
    facts->res_kind = MS_NEW_N(arena, uint8_t, nodes);
    facts->res_ref = MS_NEW_N(arena, uint32_t, nodes);
    facts->pattern_binding = MS_NEW_N(arena, uint32_t, nodes);
    facts->body_checked = MS_NEW_N(arena, bool, nodes);
    memset(facts->expr_ty, 0, nodes * sizeof *facts->expr_ty);
    memset(facts->res_kind, 0, nodes * sizeof *facts->res_kind);
    memset(facts->res_ref, 0xff, nodes * sizeof *facts->res_ref);
    memset(facts->pattern_binding, 0xff, nodes * sizeof *facts->pattern_binding);
    memset(facts->body_checked, 0, nodes * sizeof *facts->body_checked);
    // Every binding is introduced by its own syntax node, so a column per node holds them all.
    MsBindings *bindings = &facts->bindings;
    bindings->name = MS_NEW_N(arena, MsSym, nodes);
    bindings->ty = MS_NEW_N(arena, MsTy, nodes);
    bindings->decl_node = MS_NEW_N(arena, uint32_t, nodes);
    bindings->callable = MS_NEW_N(arena, uint32_t, nodes);
    bindings->flags = MS_NEW_N(arena, uint8_t, nodes);
    bindings->role = MS_NEW_N(arena, uint8_t, nodes);
    bindings->count = 0;
}

void ms_module_check_bodies(MsCheck *c, MsModId module) {
    ms_module_resolve_types(c, module);
    MsModuleRow *row = &c->mods[module];
    MsFacts *facts = row->facts;
    // A module with a declaration-level diagnostic may have signatures the bodies would restate.
    if (facts->body_checked != NULL || row->ndiags != 0) {
        return;
    }
    Body b = {.c = c,
              .module = module,
              .facts = facts,
              .int_ty = body_primitive(c, "Int"),
              .float_ty = body_primitive(c, "Float"),
              .bool_ty = body_primitive(c, "Bool"),
              .string_ty = body_primitive(c, "String"),
              .void_ty = body_primitive(c, "Void")};
    body_allocate(&b, facts);
    b.literals = ms_literal_facts_new(&c->arena, c->names, facts->node_count);
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const MsSymId sym = d->kind == MS_D_FN && !d->synthetic ? ms_decl_own_symbol(c, module, d) : MS_NONE;
        if (sym != MS_NONE) {
            body_check_function(&b, d, sym);
        }
    }
    ms_buf_free(&b.written);
}
