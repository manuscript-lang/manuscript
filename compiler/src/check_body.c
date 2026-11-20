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

#include "check_body.h"
#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"



static MsTy body_primitive(const MsCheck *c, const char *name) {
    const MsSymId sym = ms_map_get(&c->primitives, ms_intern_cstr(c->names, name));
    return sym == MS_NONE ? MS_TY_NONE : c->syms.ty[sym];
}

static bool body_is_value_type(const MsBody *b, MsTy ty) {
    return ty != MS_TY_NONE && (ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty || ty == b->string_ty);
}

/* A `type` or `enum` this module declares without type parameters. */
static bool body_is_own_nominal(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    const MsKind kind = ms_ty_kind(tys, ty);
    const uint32_t def = tys->def[ty];
    if ((kind != MS_K_TYPE && kind != MS_K_ALTERNATIVE) || tys->nargs[ty] != 0 || def == 0) {
        return false;
    }
    const MsSymId sym = def - 1;
    return sym < b->c->syms.count && b->c->syms.module[sym] == b->module && b->c->syms.kind[sym] == MS_SYM_TYPE;
}

/* A type whose values the pass can pass around: primitives, and the module's own nominal types
 * when nothing in the module could make them closeable (a value that closes gets a cleanup the
 * pass does not record yet). */
static bool body_is_admitted(const MsBody *b, MsTy ty) {
    return body_is_value_type(b, ty) || (!b->has_close && body_is_own_nominal(b, ty));
}

static bool body_is_optional(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    return ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_OPTIONAL) && tys->nargs[ty] == 1 &&
           body_is_admitted(b, ms_ty_args(tys, ty)[0]);
}

/* What a parameter or a local can hold. */
static bool body_is_bindable(const MsBody *b, MsTy ty) {
    return body_is_admitted(b, ty) || body_is_optional(b, ty);
}

static bool body_is_numeric(const MsBody *b, MsTy ty) {
    return ty == b->int_ty || ty == b->float_ty;
}

/* Gives up on the function; the caller returns `<invalid>` (MS_TY_NONE) up the tree. */
MsTy ms_body_unsupported(MsBody *b) {
    b->supported = false;
    return MS_TY_NONE;
}

static bool body_text_is(const MsBody *b, MsSym name, const char *text) {
    const MsStr s = ms_name(b->c->names, name);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

MsTy ms_body_record(MsBody *b, uint32_t node, MsTy ty) {
    b->facts->expr_ty[node] = ty;
    MS_VEC_PUSH(b->written, uint32_t, node);
    return ty;
}

/* ---- bindings ---- */

uint32_t ms_body_find_binding(const MsBody *b, MsSym name) {
    const MsBindings *bindings = &b->facts->bindings;
    for (uint32_t i = bindings->count; i > b->first_binding; i--) {
        if (bindings->name[i - 1] == name && !b->closed[i - 1]) {
            return i - 1;
        }
    }
    return MS_NONE;
}

/* Binds a name in the function's one scope. A name already bound there would be a diagnostic. */
uint32_t ms_body_bind(MsBody *b, MsSym name, MsTy ty, uint32_t node, MsPos pos, uint8_t flags, MsBindRole role) {
    if (!body_text_is(b, name, "_") && ms_body_find_binding(b, name) != MS_NONE) {
        (void)ms_body_unsupported(b);
        return MS_NONE;
    }
    MsBindings *bindings = &b->facts->bindings;
    const uint32_t id = bindings->count++;
    b->closed[id] = false;
    bindings->reads[id] = 0;
    bindings->pos[id] = pos;
    bindings->name[id] = name;
    bindings->ty[id] = ty;
    bindings->decl_node[id] = node;
    bindings->callable[id] = b->function;
    bindings->flags[id] = flags;
    bindings->role[id] = (uint8_t)role;
    return id;
}



static MsTy body_number(MsBody *b, const MsExpr *e) {
    MsCheck *c = b->c;
    const MsStr text = ms_number_canonical(&c->arena, ms_name(c->names, e->u.sym));
    if (ms_number_is_decimal(text)) {
        return ms_body_unsupported(b);
    }
    char *digits = ms_arena_strndup(&c->arena, text.ptr, text.len);
    char *end = NULL;
    errno = 0;
    if (ms_number_is_fractional(text)) {
        const double value = strtod(digits, &end);
        return *end != '\0' || isinf(value) ? ms_body_unsupported(b) : b->float_ty;
    }
    (void)strtoll(digits, &end, 10);
    return *end != '\0' || errno != 0 ? ms_body_unsupported(b) : b->int_ty;
}

static MsTy body_text(MsBody *b, const MsExpr *e) {
    for (uint32_t i = 0; i < e->u.text.len; i++) {
        const MsExpr *part = e->u.text.ptr[i].expr;
        if (part != NULL && ms_body_expr(b, part, MS_TY_NONE) == MS_TY_NONE) {
            return MS_TY_NONE;
        }
    }
    return b->string_ty;
}

/* A read of a module constant this pass has checked: a call of no arguments, typed as the
 * constant's initializer. */
static MsTy body_constant_use(MsBody *b, const MsExpr *e) {
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, e->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE || syms->module[sym] != b->module || syms->decl[sym] == NULL ||
        syms->decl[sym]->kind != MS_D_CONST || syms->ty[sym] == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[e->id] = MS_RES_SYMBOL;
    b->facts->res_ref[e->id] = sym;
    b->facts->call_callee[e->id] = sym;
    b->facts->const_use[e->id] = true;
    return b->c->tys.result[syms->ty[sym]];
}

static MsTy body_name(MsBody *b, const MsExpr *e) {
    const uint32_t binding = ms_body_find_binding(b, e->u.sym);
    if (binding == MS_NONE && !body_text_is(b, e->u.sym, "none")) {
        return body_constant_use(b, e);
    }
    if (binding == MS_NONE || body_text_is(b, e->u.sym, "none")) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[e->id] = MS_RES_BINDING;
    b->facts->res_ref[e->id] = binding;
    b->facts->bindings.reads[binding]++;
    return b->facts->bindings.ty[binding];
}

/* A call of a function this module declares, by its plain name: arguments positional, one per
 * parameter, each the parameter's type. The callee's own body is checked on its own; a callee the
 * lowering cannot handle fails the callers there. */
static MsTy body_call(MsBody *b, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    if (callee->kind != MS_E_NAME || ms_body_find_binding(b, callee->u.sym) != MS_NONE) {
        return ms_body_unsupported(b);
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, callee->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE || syms->kind[sym] != MS_SYM_FN || syms->module[sym] != b->module ||
        syms->decl[sym] == NULL || syms->nvars[sym] != 0 || syms->decl[sym]->kind != MS_D_FN ||
        syms->decl[sym]->u.fn.external) {
        return ms_body_unsupported(b);
    }
    const MsTy sig = syms->ty[sym];
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != e->u.call.args.len) {
        return ms_body_unsupported(b);
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsArg *arg = &e->u.call.args.ptr[i];
        if (arg->has_name || params[i].flags != 0 || !body_is_value_type(b, params[i].ty) ||
            ms_body_expr(b, arg->value, params[i].ty) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    b->facts->call_callee[e->id] = sym;
    const MsTy result = tys->result[sig];
    return body_is_value_type(b, result) ? result : ms_body_unsupported(b);
}

static MsTy body_unary(MsBody *b, const MsExpr *e) {
    const MsExpr *operand = e->u.bin.left;
    const MsUnaryOp op = (MsUnaryOp)e->op;
    if (op == MS_U_TRY) {
        return ms_body_unsupported(b);
    }
    if (op == MS_U_NEG && operand->kind == MS_E_NUMBER) {
        // A negated literal is typed as the literal; -9223372036854775808 is Int's own case.
        const MsStr text = ms_number_canonical(&b->c->arena, ms_name(b->c->names, operand->u.sym));
        if (text.len == 19 && memcmp(text.ptr, "9223372036854775808", 19) == 0) {
            return ms_body_unsupported(b);
        }
        const MsTy literal = body_number(b, operand);
        return literal == MS_TY_NONE ? literal : ms_body_record(b, operand->id, literal);
    }
    const MsTy operand_ty = ms_body_expr(b, operand, MS_TY_NONE);
    if (operand_ty == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    if (op == MS_U_NOT) {
        return operand_ty == b->bool_ty ? b->bool_ty : ms_body_unsupported(b);
    }
    return body_is_numeric(b, operand_ty) ? operand_ty : ms_body_unsupported(b);
}

/* `local.field` where the local holds a record this module declares and the field is a Copy
 * primitive (Int, Float, Bool): the field's type. Anything else a member can be (a method, a case, a module path)
 * is not checked yet. */
static MsTy body_member(MsBody *b, const MsExpr *e) {
    const MsExpr *receiver = e->u.member.left;
    if (receiver->kind != MS_E_NAME) {
        return ms_body_unsupported(b);
    }
    const MsTy record = ms_body_expr(b, receiver, MS_TY_NONE);
    if (record == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, record) != MS_K_TYPE || !body_is_own_nominal(b, record)) {
        return ms_body_unsupported(b);
    }
    const MsDef *def = ms_def(b->c, tys->def[record] - 1);
    for (uint32_t i = 0; def != NULL && i < def->nfields; i++) {
        if (def->fields[i].name != e->u.member.name) {
            continue;
        }
        if (!body_is_value_type(b, def->fields[i].ty) || def->fields[i].ty == b->string_ty) {
            break; /* reading a String field borrows or moves it out of its holder */
        }
        b->facts->res_kind[e->id] = MS_RES_FIELD;
        b->facts->res_ref[e->id] = i;
        return def->fields[i].ty;
    }
    return ms_body_unsupported(b);
}

static bool body_is_ordering(MsBinaryOp op) {
    return op == MS_B_LT || op == MS_B_GT || op == MS_B_LE || op == MS_B_GE;
}

/* Integer arithmetic over constants that always faults is a diagnostic. */
static bool body_constant_fault(MsBody *b, const MsExpr *e) {
    const MsStr fault = ms_constant_arithmetic_fault(&b->c->arena, b->literals, (MsBinaryOp)e->op, e->u.bin.left,
                                                     e->u.bin.right, "Int", INT64_MIN, INT64_MAX);
    return fault.len != 0;
}

static MsStr body_show(MsBody *b, MsTy ty);

/* What to do about operands of two different primitive types: Int with Float, or text with a
 * number for `*`, have their own hint. */
static const char *body_operand_hint(const MsBody *b, MsBinaryOp op, MsTy left, MsTy right) {
    const bool mixed = (left == b->int_ty && right == b->float_ty) || (left == b->float_ty && right == b->int_ty);
    if (mixed) {
        return "convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)";
    }
    const bool repeat = (left == b->string_ty && right == b->int_ty) || (left == b->int_ty && right == b->string_ty);
    if (repeat && op == MS_B_MUL) {
        return "to repeat text write text.repeat(count), which returns a Result (append '?' to propagate it)";
    }
    return "convert one side so both have one type (e.g. interpolate into text with f\"{value}\", or convert "
           "between Int and Float)";
}

/* Operands of two primitive types that differ: reported at the operator, and the whole is
 * invalid (a comparison is still Bool), which silences whatever uses it. */
static MsTy body_report_operands(MsBody *b, const MsExpr *e, MsTy left, MsTy right) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    const MsStr l = body_show(b, left);
    const MsStr r = body_show(b, right);
    const MsStr message = ms_arena_fmt(
        &b->c->arena, "operator operands require the same independently known type, found %.*s %s %.*s; %s", (int)l.len,
        l.ptr, ms_binary_str(op), (int)r.len, r.ptr, body_operand_hint(b, op, left, right));
    const MsCheckDiag diag = {.diag = {.pos = e->pos, .message = message}, .phase = MS_PHASE_TYPE};
    MS_VEC_PUSH(b->diags, MsCheckDiag, diag);
    const bool comparison = op == MS_B_EQ || op == MS_B_NE || body_is_ordering(op);
    return comparison ? b->bool_ty : b->invalid_ty;
}

static MsTy body_binary(MsBody *b, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    const MsTy left = ms_body_expr(b, e->u.bin.left, MS_TY_NONE);
    const MsTy right = left == MS_TY_NONE ? MS_TY_NONE : ms_body_expr(b, e->u.bin.right, MS_TY_NONE);
    if (right == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const bool comparison = op == MS_B_EQ || op == MS_B_NE || body_is_ordering(op);
    if (left == b->invalid_ty || right == b->invalid_ty) {
        // An operand already reported its own error; this one does not restate it.
        return comparison || op == MS_B_AND || op == MS_B_OR ? b->bool_ty : b->invalid_ty;
    }
    if (op == MS_B_AND || op == MS_B_OR) {
        return left == b->bool_ty && right == b->bool_ty ? b->bool_ty : ms_body_unsupported(b);
    }
    if (left != right && body_is_value_type(b, left) && body_is_value_type(b, right)) {
        return body_report_operands(b, e, left, right);
    }
    if (left != right || !body_is_value_type(b, left)) {
        return ms_body_unsupported(b);
    }
    if (op == MS_B_EQ || op == MS_B_NE) {
        return b->bool_ty;
    }
    if (body_is_ordering(op)) {
        return left == b->bool_ty ? ms_body_unsupported(b) : b->bool_ty;
    }
    if (left == b->string_ty) {
        return op == MS_B_ADD ? left : ms_body_unsupported(b);
    }
    const bool numeric = body_is_numeric(b, left);
    const bool remainder_of_float = op == MS_B_REM && left != b->int_ty;
    if (!numeric || remainder_of_float || (left == b->int_ty && body_constant_fault(b, e))) {
        return ms_body_unsupported(b);
    }
    return left;
}

/* ---- diagnostics ---- */

static MsStr body_show(MsBody *b, MsTy ty) {
    MsBuf text = {0};
    ms_ty_show(&text, b->c->names, &b->c->tys, ty);
    const MsStr shown = ms_arena_fmt(&b->c->arena, "%.*s", (int)text.len, (const char *)text.data);
    ms_buf_free(&text);
    return shown;
}

/* What the implicit conversion between two primitives would be, written out; "" for none. */
static const char *body_conversion_hint(const MsBody *b, MsTy actual, MsTy expected) {
    if (actual == b->int_ty && expected == b->float_ty) {
        return "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value";
    }
    if (actual == b->float_ty && expected == b->int_ty) {
        return "Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get(0)";
    }
    if (expected == b->string_ty && (actual == b->int_ty || actual == b->float_ty || actual == b->bool_ty)) {
        if (actual == b->int_ty) {
            return "Int does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\"";
        }
        if (actual == b->float_ty) {
            return "Float does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\"";
        }
        return "Bool does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\"";
    }
    return "";
}

/* "expected X, found Y (in <context>)" at `e`, with the conversion hint where one applies. */
static void body_report_mismatch(MsBody *b, const MsExpr *e, MsTy actual, MsTy expected, const char *context) {
    const MsStr want = body_show(b, expected);
    const MsStr found = body_show(b, actual);
    const char *hint = body_conversion_hint(b, actual, expected);
    const MsStr message = ms_arena_fmt(&b->c->arena, "expected %.*s, found %.*s (in %s)%s%s", (int)want.len, want.ptr,
                                       (int)found.len, found.ptr, context, *hint != '\0' ? "; " : "", hint);
    const MsCheckDiag diag = {.diag = {.pos = e->pos, .message = message}, .phase = MS_PHASE_TYPE};
    MS_VEC_PUSH(b->diags, MsCheckDiag, diag);
}

/* The type of `e` where `expected` is the type the context wants, or MS_TY_NONE for no
 * expectation. A type that is not the expected one is a diagnostic. */
MsTy ms_body_expr(MsBody *b, const MsExpr *e, MsTy expected) {
    MsTy ty = MS_TY_NONE;
    const char *context = b->context;
    b->context = NULL;
    // A value checked against an Optional may be wrapped in `some`; that is not recorded yet.
    if (expected != MS_TY_NONE && ms_ty_is(&b->c->tys, expected, MS_BI_OPTIONAL)) {
        return ms_body_unsupported(b);
    }
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: ty = body_number(b, e); break;
    case MS_E_BOOL: ty = b->bool_ty; break;
    case MS_E_VOID: ty = b->void_ty; break;
    case MS_E_TEXT: ty = body_text(b, e); break;
    case MS_E_NAME: ty = body_name(b, e); break;
    case MS_E_UNARY: ty = body_unary(b, e); break;
    case MS_E_BINARY: ty = body_binary(b, e); break;
    case MS_E_MEMBER: ty = body_member(b, e); break;
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA: return ms_body_unsupported(b);
    case MS_E_CALL: ty = body_call(b, e); break;
    case MS_E_MATCH: ty = ms_body_match(b, e, expected); break;
    }
    if (ty == MS_TY_NONE) {
        return ty;
    }
    if (ty == b->invalid_ty) {
        // Already reported where it went wrong; nothing built on it is.
        (void)ms_body_record(b, e->id, ty);
        return expected != MS_TY_NONE ? expected : ty;
    }
    if (expected != MS_TY_NONE && ty != expected) {
        // A value of the wrong primitive type is reported where the statement asked for it; the
        // statement goes on as if it had the expected type, as the Rust checker does.
        if (context == NULL || !body_is_value_type(b, ty) || !body_is_value_type(b, expected)) {
            return ms_body_unsupported(b);
        }
        body_report_mismatch(b, e, ty, expected, context);
        (void)ms_body_record(b, e->id, ty);
        return expected;
    }
    return ms_body_record(b, e->id, ty);
}

/* ---- statements ---- */

/* The primitive type a written annotation names, or MS_TY_NONE. */
static MsTy body_annotation(MsBody *b, const MsTypeRef *t) {
    if (t->kind != MS_TYPE_NAMED || t->args.len != 0) {
        return ms_body_unsupported(b);
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
    const MsTy ty = sym == MS_NONE ? MS_TY_NONE : b->c->syms.ty[sym];
    if (!body_is_value_type(b, ty) || b->c->syms.decl[sym] != NULL) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

static void body_bind_statement(MsBody *b, const MsStmt *s) {
    const MsPattern *pattern = s->u.bind.pattern;
    if (pattern->kind != MS_P_NAME || s->u.bind.has_group) {
        (void)ms_body_unsupported(b);
        return;
    }
    const MsTy expected = s->u.bind.ty == NULL ? MS_TY_NONE : body_annotation(b, s->u.bind.ty);
    if (!b->supported) {
        return;
    }
    if (expected != MS_TY_NONE) {
        const MsStr name = ms_name(b->c->names, pattern->u.name);
        b->context = ms_arena_fmt(&b->c->arena, "the initializer of '%.*s'", (int)name.len, name.ptr).ptr;
    }
    const MsTy value = ms_body_expr(b, s->u.bind.value, expected);
    if (value == MS_TY_NONE || !body_is_bindable(b, value)) {
        (void)ms_body_unsupported(b);
        return;
    }
    const uint8_t flags = s->u.bind.is_mutable ? MS_BIND_MUTABLE : 0;
    const MsBindRole role = s->u.bind.is_mutable ? MS_ROLE_VAR : MS_ROLE_LET;
    const uint32_t binding = ms_body_bind(b, pattern->u.name, value, pattern->id, pattern->pos, flags, role);
    if (binding != MS_NONE) {
        b->facts->pattern_binding[pattern->id] = binding;
    }
}

/* `name = value` and `name op= value` (the parser writes the second as `name = name op value`).
 * Reads of the name inside the value only feed its next value, so they do not count as reads. */
static void body_assign_statement(MsBody *b, const MsStmt *s) {
    if (s->u.assign.member_target) {
        (void)ms_body_unsupported(b);
        return;
    }
    const uint32_t binding = ms_body_find_binding(b, s->u.assign.name);
    if (binding == MS_NONE || (b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) == 0) {
        (void)ms_body_unsupported(b);
        return;
    }
    uint32_t *reads = &b->facts->bindings.reads[binding];
    const uint32_t reads_before = *reads;
    (void)ms_body_expr(b, s->u.assign.value, b->facts->bindings.ty[binding]);
    if (*reads != reads_before) {
        b->facts->bindings.flags[binding] |= MS_BIND_FED;
    }
    *reads = reads_before;
    b->facts->assign_binding[s->id] = binding;
}

static void body_return_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *value = s->u.expr;
    if (value == NULL) {
        b->supported = b->supported && b->result == b->void_ty;
        return;
    }
    b->context = "the return value";
    (void)ms_body_expr(b, value, b->result);
}


/* Checks a condition against `Bool`, then the branches; whether control can leave the statement. */
static bool body_if_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *cond = s->u.branch.cond;
    b->context = "an if condition";
    if (s->u.branch.binding != NULL || ms_body_expr(b, cond, b->bool_ty) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const bool then_falls = ms_body_block(b, &s->u.branch.body);
    const bool else_falls = s->u.branch.else_body.len == 0 || ms_body_block(b, &s->u.branch.else_body);
    return then_falls || else_falls;
}

static bool body_while_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *cond = s->u.loop.cond;
    b->context = "a while condition";
    if (ms_body_expr(b, cond, b->bool_ty) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const uint32_t outer_breaks = b->breaks;
    b->breaks = 0;
    b->loop_depth++;
    (void)ms_body_block(b, &s->u.loop.body);
    b->loop_depth--;
    const bool broke = b->breaks != 0;
    b->breaks = outer_breaks;
    // `while true` ends only through a `break`.
    return broke || !(cond->kind == MS_E_BOOL && cond->u.flag);
}

/* `break` and `continue` leave the innermost loop; outside one they are a diagnostic. */
static void body_jump_statement(MsBody *b, const MsStmt *s) {
    if (b->loop_depth == 0) {
        (void)ms_body_unsupported(b);
        return;
    }
    b->breaks += s->kind == MS_S_BREAK;
}

/* Checks the statements of a nested scope in order; whether control falls out of the end. A
 * statement after one that never falls through is left to the Rust checker. */
/* Checks the statements in the current scope; whether control falls out of the end. */
static bool body_run(MsBody *b, const MsStmts *body) {
    bool falls = true;
    for (uint32_t i = 0; i < body->len && b->supported; i++) {
        const MsStmt *s = body->ptr[i];
        if (!falls) {
            (void)ms_body_unsupported(b);
            break;
        }
        switch ((MsStmtKind)s->kind) {
        case MS_S_BIND: body_bind_statement(b, s); break;
        case MS_S_RETURN:
            body_return_statement(b, s);
            falls = false;
            break;
        case MS_S_IF: falls = body_if_statement(b, s); break;
        case MS_S_WHILE: falls = body_while_statement(b, s); break;
        case MS_S_ASSIGN: body_assign_statement(b, s); break;
        case MS_S_BREAK:
        case MS_S_CONTINUE:
            body_jump_statement(b, s);
            falls = false;
            break;
        case MS_S_CALL:
        case MS_S_FOR: (void)ms_body_unsupported(b); break;
        }
    }
    return falls;
}

static void body_close_scope(MsBody *b, uint32_t scope_start) {
    for (uint32_t i = scope_start; i < b->facts->bindings.count; i++) {
        b->closed[i] = true;
    }
}

bool ms_body_block(MsBody *b, const MsStmts *body) {
    const uint32_t scope_start = b->facts->bindings.count;
    const bool falls = body_run(b, body);
    body_close_scope(b, scope_start);
    return falls;
}

MsTy ms_body_block_value(MsBody *b, const MsStmts *body, const MsExpr *value, MsTy expected) {
    const uint32_t scope_start = b->facts->bindings.count;
    const bool falls = body_run(b, body);
    MsTy ty = MS_TY_NONE;
    if (b->supported && falls) {
        ty = ms_body_expr(b, value, expected);
    } else {
        (void)ms_body_unsupported(b);
    }
    body_close_scope(b, scope_start);
    return ty;
}

static void body_statements(MsBody *b, const MsStmts *body) {
    const bool falls = ms_body_block(b, body);
    // A function that returns a value must end every path with a `return`.
    if (b->supported && falls && b->result != b->void_ty) {
        (void)ms_body_unsupported(b);
    }
}

/* ---- functions ---- */

/* Reports the diagnostics a claimed function collected, from `first` on. */
static void body_commit_diags(MsBody *b, size_t first) {
    const MsCheckDiag *diags = ms_buf_items(&b->diags);
    for (size_t i = first; i < MS_VEC_LEN(b->diags, MsCheckDiag); i++) {
        ms_report(b->c, b->module, &diags[i]);
    }
    b->diags.len = first * sizeof(MsCheckDiag);
}

static void body_undo(MsBody *b, uint32_t first_binding, size_t written_start, size_t diags_start) {
    const uint32_t *ids = ms_buf_items(&b->written);
    for (size_t i = written_start; i < MS_VEC_LEN(b->written, uint32_t); i++) {
        b->facts->expr_ty[ids[i]] = MS_TY_NONE;
        b->facts->res_kind[ids[i]] = MS_RES_NONE;
        b->facts->res_ref[ids[i]] = MS_NONE;
        b->facts->call_callee[ids[i]] = MS_NONE;
        b->facts->const_use[ids[i]] = false;
    }
    b->written.len = written_start * sizeof(uint32_t);
    b->diags.len = diags_start * sizeof(MsCheckDiag);
    b->facts->bindings.count = first_binding;
}

/* A parameter has no default, or the `none` of an `Optional` (which `T?` implies). */
static bool body_default_is_none(const MsBody *b, const MsParam *p) {
    return p->def == NULL || (p->def->kind == MS_E_NAME && body_text_is(b, p->def->u.sym, "none"));
}

static bool body_signature_supported(const MsBody *b, const MsFunc *fn, MsTy sig) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != fn->params.len || fn->type_params.len != 0) {
        return false;
    }
    const MsTy result = tys->result[sig];
    if (!body_is_admitted(b, result) && result != b->void_ty) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MsParam *p = fn->params.ptr[i];
        if (!body_default_is_none(b, p) || p->is_mutable || p->moving || !body_is_bindable(b, params[i].ty)) {
            return false;
        }
    }
    return true;
}

static void body_check_function(MsBody *b, const MsDecl *d, MsSymId sym) {
    const MsFunc *fn = &d->u.fn;
    const MsTy sig = b->c->syms.ty[sym];
    if (fn->external || b->c->syms.nvars[sym] != 0 || !body_signature_supported(b, fn, sig)) {
        return;
    }
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
    b->first_binding = first_binding;
    b->function = d->id;
    b->supported = true;
    b->result = b->c->tys.result[sig];
    const MsTyParam *params = ms_ty_params(&b->c->tys, sig);
    for (uint32_t i = 0; i < fn->params.len && b->supported; i++) {
        (void)ms_body_bind(b, params[i].name, params[i].ty, fn->params.ptr[i]->id, fn->params.ptr[i]->pos, 0, MS_ROLE_PARAM);
    }
    if (b->supported) {
        body_statements(b, &fn->body);
    }
    if (b->supported) {
        b->facts->body_checked[d->id] = true;
        body_commit_diags(b, diags_start);
    } else {
        body_undo(b, first_binding, written_start, diags_start);
    }
}

static void body_allocate(MsBody *b, MsFacts *facts) {
    MsArena *arena = &b->c->arena;
    const size_t nodes = (size_t)facts->node_count + 1;
    b->closed = MS_NEW_N(arena, bool, nodes);
    memset(b->closed, 0, nodes * sizeof *b->closed);
    facts->expr_ty = MS_NEW_N(arena, MsTy, nodes);
    facts->res_kind = MS_NEW_N(arena, uint8_t, nodes);
    facts->res_ref = MS_NEW_N(arena, uint32_t, nodes);
    facts->pattern_binding = MS_NEW_N(arena, uint32_t, nodes);
    facts->arm_case = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->arm_case, 0xff, nodes * sizeof *facts->arm_case);
    facts->body_checked = MS_NEW_N(arena, bool, nodes);
    facts->const_use = MS_NEW_N(arena, bool, nodes);
    memset(facts->const_use, 0, nodes * sizeof *facts->const_use);
    facts->call_callee = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->call_callee, 0xff, nodes * sizeof *facts->call_callee);
    facts->assign_binding = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->assign_binding, 0xff, nodes * sizeof *facts->assign_binding);
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
    bindings->reads = MS_NEW_N(arena, uint32_t, nodes);
    bindings->pos = MS_NEW_N(arena, MsPos, nodes);
    bindings->flags = MS_NEW_N(arena, uint8_t, nodes);
    bindings->role = MS_NEW_N(arena, uint8_t, nodes);
    bindings->count = 0;
}

static MsTy body_invalid(MsCheck *c) {
    const MsSym name = ms_intern_cstr(c->names, "<invalid>");
    const MsTyDesc desc = {.name = name, .id = name, .kind = MS_K_INVALID};
    return ms_ty_intern(&c->tys, &desc);
}

/* Whether the module declares a method called `close`, inside an `impl` or as `fn Type.close`. */
static bool body_module_has_close(const MsCheck *c, const MsModule *syntax) {
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind == MS_D_FN) {
            const MsStr name = ms_name(c->names, d->u.fn.name);
            if (name.len >= 6 && memcmp(name.ptr + name.len - 6, ".close", 6) == 0) {
                return true;
            }
        }
        if (d->kind != MS_D_IMPL) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            const MsStr name = ms_name(c->names, d->u.impl.methods.ptr[k]->func.name);
            if (name.len == 5 && memcmp(name.ptr, "close", 5) == 0) {
                return true;
            }
        }
    }
    return false;
}

/* Whether a constant's initializer is literals, text and operators alone: a call, a name or a
 * member in it is another rule's concern (a constant may name only other constants). */
static bool body_is_constant_expression(const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID: return true;
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            const MsExpr *part = e->u.text.ptr[i].expr;
            if (part != NULL && !body_is_constant_expression(part)) {
                return false;
            }
        }
        return true;
    case MS_E_UNARY: return body_is_constant_expression(e->u.bin.left);
    case MS_E_BINARY: return body_is_constant_expression(e->u.bin.left) && body_is_constant_expression(e->u.bin.right);
    default: return false;
    }
}

/* A module constant `NAME := value` (or `NAME: Type := value`) whose initializer is literals and
 * operators. The Rust checker types it as a function of no parameters, in a scope of its own. */
static void body_check_constant(MsBody *b, const MsDecl *d, MsSymId sym) {
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
    b->first_binding = first_binding;
    b->function = d->id;
    b->supported = true;
    MsTy expected = MS_TY_NONE;
    if (d->u.konst.ty != NULL) {
        expected = body_annotation(b, d->u.konst.ty);
    }
    const bool literal = body_is_constant_expression(d->u.konst.value);
    const MsTy ty = b->supported && literal ? ms_body_expr(b, d->u.konst.value, expected) : MS_TY_NONE;
    if (b->supported && literal && body_is_value_type(b, ty)) {
        b->facts->body_checked[d->id] = true;
        body_commit_diags(b, diags_start);
        // Like the Rust checker's, the constant's symbol is a function of no parameters.
        const MsSym fn = ms_intern_cstr(b->c->names, "fn");
        const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_K_FUNCTION, .result = ty};
        b->c->syms.ty[sym] = ms_ty_intern(&b->c->tys, &desc);
    } else {
        body_undo(b, first_binding, written_start, diags_start);
    }
}

void ms_module_check_bodies(MsCheck *c, MsModId module) {
    ms_module_resolve_types(c, module);
    MsModuleRow *row = &c->mods[module];
    MsFacts *facts = row->facts;
    // A module with a declaration-level diagnostic may have signatures the bodies would restate.
    if (facts->body_checked != NULL || row->ndiags != 0) {
        return;
    }
    MsBody b = {.c = c,
              .module = module,
              .facts = facts,
              .int_ty = body_primitive(c, "Int"),
              .float_ty = body_primitive(c, "Float"),
              .bool_ty = body_primitive(c, "Bool"),
              .string_ty = body_primitive(c, "String"),
              .void_ty = body_primitive(c, "Void"),
              .invalid_ty = body_invalid(c),
              .has_close = body_module_has_close(c, row->syntax)};
    body_allocate(&b, facts);
    b.literals = ms_literal_facts_new(&c->arena, c->names, facts->node_count);
    // Constants first: a function reads them wherever they are declared.
    for (uint32_t pass = 0; pass < 2; pass++) {
        const MsDeclKind kind = pass == 0 ? MS_D_CONST : MS_D_FN;
        for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
            const MsDecl *d = row->syntax->decls[i];
            const MsSymId sym = d->kind == kind && !d->synthetic ? ms_decl_own_symbol(c, module, d) : MS_NONE;
            if (sym == MS_NONE) {
                continue;
            }
            if (kind == MS_D_FN) {
                body_check_function(&b, d, sym);
            } else {
                body_check_constant(&b, d, sym);
            }
        }
    }
    ms_buf_free(&b.written);
    ms_buf_free(&b.diags);
}
