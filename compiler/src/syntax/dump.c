/* The canonical tree dump of crates/ms-syntax/src/dump.rs, in C: every node prints all of its
 * fields in one fixed order, so two trees are equal exactly when their dumps are. Nothing here
 * owns memory; the dump goes to a caller's MsBuf. */
#include <string.h>

#include "ms/dump.h"

typedef struct TreeDump {
    MsBuf *out;
    const MsNames *names;
} TreeDump;

static void tree_put(TreeDump *d, const char *text) {
    ms_buf_puts(d->out, text);
}

static void tree_put_pos(TreeDump *d, MsPos pos) {
    ms_dump_pos(d->out, pos);
}

static void tree_put_quoted(TreeDump *d, MsStr text) {
    ms_dump_quote(d->out, text.ptr, text.len);
}

static void tree_put_quoted_c(TreeDump *d, const char *text) {
    ms_dump_quote(d->out, text, strlen(text));
}

static void tree_put_name(TreeDump *d, MsSym name) {
    tree_put_quoted(d, ms_name(d->names, name));
}

static void tree_dump_type(TreeDump *d, const MsTypeRef *type);
static void tree_dump_expr(TreeDump *d, const MsExpr *expr);
static void tree_dump_params(TreeDump *d, MsParams params);
static void tree_dump_body(TreeDump *d, MsStmts body);
static void tree_dump_pattern(TreeDump *d, const MsPattern *pattern);

/* ---- types and parameters ---- */

static void tree_dump_types(TreeDump *d, MsTypeRefs types) {
    tree_put(d, "[");
    for (uint32_t i = 0; i < types.len; i++) {
        tree_dump_type(d, types.ptr[i]);
        tree_put(d, " ");
    }
    tree_put(d, "]");
}

static void tree_dump_type(TreeDump *d, const MsTypeRef *type) {
    if (type == NULL) {
        tree_put(d, "nil");
        return;
    }
    tree_put(d, "(type ");
    tree_put_pos(d, type->pos);
    tree_put(d, " ");
    if (type->kind == MS_TYPE_NAMED) {
        tree_put_name(d, type->name);
        tree_put(d, " ");
        tree_dump_types(d, type->args);
        tree_put(d, " ");
        tree_dump_params(d, (MsParams){0});
        tree_put(d, " nil)");
        return;
    }
    tree_put_quoted_c(d, "fn");
    tree_put(d, " ");
    tree_dump_types(d, (MsTypeRefs){0});
    tree_put(d, " ");
    tree_dump_params(d, type->params);
    tree_put(d, " ");
    tree_dump_type(d, type->result);
    tree_put(d, ")");
}

/* A type the parser never wrote: the placeholder result of a constant, or the Void of a test. */
static void tree_dump_synthetic_type(TreeDump *d, MsPos pos, const char *name) {
    tree_put(d, "(type ");
    tree_put_pos(d, pos);
    tree_put(d, " ");
    tree_put_quoted_c(d, name);
    tree_put(d, " [] [] nil)");
}

static void tree_dump_params(TreeDump *d, MsParams params) {
    tree_put(d, "[");
    for (uint32_t i = 0; i < params.len; i++) {
        const MsParam *param = params.ptr[i];
        tree_put(d, "(param ");
        tree_put_pos(d, param->pos);
        tree_put(d, " ");
        tree_put_name(d, param->name);
        tree_put(d, " ");
        tree_dump_type(d, param->ty);
        tree_put(d, " ");
        tree_dump_expr(d, param->def);
        tree_put(d, ") ");
    }
    tree_put(d, "]");
}

/* ---- expressions ---- */

/* Every field an expression can print, in print order; a kind sets the ones it has. */
typedef struct TreeExprFields {
    const char *kind;
    const MsExpr *left;
    const MsExpr *right;
    const MsArg *args;
    MsTypeRef **types;
    MsExpr **elements;
    const MsMapEntry *entries;
    const MsTextPart *parts;
    MsParam **params;
    const MsTypeRef *result;
    MsStmt **body;
    MsArm **arms;
    MsStr text;
    uint32_t arg_count;
    uint32_t type_count;
    uint32_t element_count;
    uint32_t entry_count;
    uint32_t part_count;
    uint32_t param_count;
    uint32_t body_count;
    uint32_t arm_count;
} TreeExprFields;

static MsStr tree_text_of(const char *text) {
    return (MsStr){.ptr = text, .len = (uint32_t)strlen(text)};
}

static void tree_dump_args(TreeDump *d, const MsArg *args, uint32_t count) {
    tree_put(d, " [");
    for (uint32_t i = 0; i < count; i++) {
        tree_put(d, "(arg ");
        tree_put_pos(d, args[i].pos);
        tree_put(d, " ");
        if (args[i].has_name) {
            tree_put_name(d, args[i].name);
        } else {
            tree_put_quoted_c(d, "");
        }
        tree_put(d, " ");
        tree_dump_expr(d, args[i].value);
        tree_put(d, ") ");
    }
    tree_put(d, "] ");
}

static void tree_dump_elements(TreeDump *d, const TreeExprFields *f) {
    tree_put(d, " [");
    for (uint32_t i = 0; i < f->element_count; i++) {
        tree_dump_expr(d, f->elements[i]);
        tree_put(d, " ");
    }
    for (uint32_t i = 0; i < f->entry_count; i++) {
        tree_dump_expr(d, f->entries[i].key);
        tree_put(d, " ");
        tree_dump_expr(d, f->entries[i].value);
        tree_put(d, " ");
    }
    tree_put(d, "] [");
}

static void tree_dump_parts(TreeDump *d, const MsTextPart *parts, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        tree_put(d, "(part ");
        if (parts[i].expr == NULL) {
            tree_put_quoted(d, parts[i].lit);
            tree_put(d, " nil");
        } else {
            tree_put_quoted_c(d, "");
            tree_put(d, " ");
            tree_dump_expr(d, parts[i].expr);
        }
        tree_put(d, ") ");
    }
    tree_put(d, "] ");
}

static void tree_dump_arms(TreeDump *d, MsArm **arms, uint32_t count) {
    tree_put(d, " [");
    for (uint32_t i = 0; i < count; i++) {
        const MsArm *arm = arms[i];
        tree_put(d, "(arm ");
        tree_put_pos(d, arm->pos);
        tree_put(d, " ");
        tree_dump_expr(d, arm->path);
        tree_put(d, " [");
        for (uint32_t k = 0; k < arm->bindings.len; k++) {
            tree_put(d, "(");
            tree_put_name(d, arm->bindings.ptr[k].name);
            tree_put(d, " ");
            tree_put_pos(d, arm->bindings.ptr[k].pos);
            tree_put(d, ") ");
        }
        tree_put(d, "] ");
        tree_dump_body(d, arm->body);
        tree_put(d, " ");
        tree_dump_expr(d, arm->value);
        tree_put(d, ") ");
    }
    tree_put(d, "])");
}

static void tree_dump_expr_fields(TreeDump *d, const MsExpr *expr, const TreeExprFields *f) {
    tree_put(d, "(expr ");
    tree_put_pos(d, expr->pos);
    tree_put(d, " ");
    tree_put(d, f->kind);
    tree_put(d, " ");
    tree_put_quoted(d, f->text);
    tree_put(d, " ");
    tree_dump_expr(d, f->left);
    tree_put(d, " ");
    tree_dump_expr(d, f->right);
    tree_dump_args(d, f->args, f->arg_count);
    tree_dump_types(d, (MsTypeRefs){.ptr = f->types, .len = f->type_count});
    tree_dump_elements(d, f);
    tree_dump_parts(d, f->parts, f->part_count);
    tree_dump_params(d, (MsParams){.ptr = f->params, .len = f->param_count});
    tree_put(d, " ");
    tree_dump_type(d, f->result);
    tree_put(d, " ");
    tree_dump_body(d, (MsStmts){.ptr = f->body, .len = f->body_count});
    tree_dump_arms(d, f->arms, f->arm_count);
}

static TreeExprFields tree_leaf_fields(const TreeDump *d, const MsExpr *e) {
    TreeExprFields f = {0};
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
        f.kind = "number";
        f.text = ms_name(d->names, e->u.sym);
        break;
    case MS_E_BOOL:
        f.kind = "bool";
        f.text = tree_text_of(e->u.flag ? "true" : "false");
        break;
    case MS_E_VOID:
        f.kind = "void";
        f.text = tree_text_of("void");
        break;
    case MS_E_NAME:
        f.kind = "name";
        f.text = ms_name(d->names, e->u.sym);
        break;
    case MS_E_TEXT:
        f.kind = "text";
        f.parts = e->u.text.ptr;
        f.part_count = e->u.text.len;
        break;
    case MS_E_MEMBER:
        f.kind = "member";
        f.text = ms_name(d->names, e->u.member.name);
        f.left = e->u.member.left;
        break;
    default:
        break;
    }
    return f;
}

static TreeExprFields tree_access_fields(const MsExpr *e) {
    TreeExprFields f = {0};
    switch ((MsExprKind)e->kind) {
    case MS_E_APPLY:
        f.kind = "apply";
        f.left = e->u.apply.left;
        f.right = e->u.apply.value;
        f.types = e->u.apply.types.ptr;
        f.type_count = e->u.apply.types.len;
        break;
    case MS_E_INDEX:
        f.kind = "index";
        f.left = e->u.bin.left;
        f.right = e->u.bin.right;
        break;
    case MS_E_PROBE:
        f.kind = "probe";
        f.left = e->u.bin.left;
        break;
    case MS_E_LIST:
        f.kind = "list";
        f.text = tree_text_of("[");
        f.elements = e->u.list.ptr;
        f.element_count = e->u.list.len;
        break;
    case MS_E_MAP:
        f.kind = "map";
        f.text = tree_text_of("{");
        f.entries = e->u.map.ptr;
        f.entry_count = e->u.map.len;
        break;
    default:
        break;
    }
    return f;
}

static TreeExprFields tree_operator_fields(const MsExpr *e) {
    TreeExprFields f = {0};
    if (e->kind == MS_E_UNARY) {
        f.kind = "unary";
        f.text = tree_text_of(ms_unary_str((MsUnaryOp)e->op));
        f.right = e->u.bin.left;
    } else {
        f.kind = "binary";
        f.text = tree_text_of(ms_binary_str((MsBinaryOp)e->op));
        f.left = e->u.bin.left;
        f.right = e->u.bin.right;
    }
    return f;
}

static TreeExprFields tree_compound_fields(const MsExpr *e) {
    TreeExprFields f = {0};
    switch ((MsExprKind)e->kind) {
    case MS_E_LAMBDA:
        f.kind = "lambda";
        f.params = e->u.lambda.params.ptr;
        f.param_count = e->u.lambda.params.len;
        f.result = e->u.lambda.result;
        f.body = e->u.lambda.body.ptr;
        f.body_count = e->u.lambda.body.len;
        break;
    case MS_E_CALL:
        f.kind = "call";
        f.left = e->u.call.callee;
        f.args = e->u.call.args.ptr;
        f.arg_count = e->u.call.args.len;
        break;
    case MS_E_MATCH:
        f.kind = "match";
        f.text = tree_text_of("match");
        f.left = e->u.match.scrutinee;
        f.arms = e->u.match.arms.ptr;
        f.arm_count = e->u.match.arms.len;
        break;
    default:
        break;
    }
    return f;
}

static TreeExprFields tree_expr_fields(const TreeDump *d, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_NAME:
    case MS_E_TEXT:
    case MS_E_MEMBER:
        return tree_leaf_fields(d, e);
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
        return tree_access_fields(e);
    case MS_E_UNARY:
    case MS_E_BINARY:
        return tree_operator_fields(e);
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH:
        return tree_compound_fields(e);
    }
    return (TreeExprFields){0};
}

static void tree_dump_expr(TreeDump *d, const MsExpr *expr) {
    if (expr == NULL) {
        tree_put(d, "nil");
        return;
    }
    TreeExprFields fields = tree_expr_fields(d, expr);
    tree_dump_expr_fields(d, expr, &fields);
}

/* ---- patterns ---- */

static void tree_dump_pattern_fields(TreeDump *d, const MsPattern *pattern) {
    switch ((MsPatternKind)pattern->kind) {
    case MS_P_NAME:
        tree_put(d, "name ");
        tree_put_name(d, pattern->u.name);
        tree_put(d, " [] []");
        return;
    case MS_P_LIST:
        tree_put(d, "list ");
        tree_put_quoted_c(d, "");
        tree_put(d, " [");
        for (uint32_t i = 0; i < pattern->u.list.len; i++) {
            tree_dump_pattern(d, pattern->u.list.ptr[i]);
            tree_put(d, " ");
        }
        tree_put(d, "] []");
        return;
    case MS_P_TYPE:
        tree_put(d, "type ");
        tree_put_quoted_c(d, "");
        tree_put(d, " [] [");
        for (uint32_t i = 0; i < pattern->u.fields.len; i++) {
            const MsPatternField *field = &pattern->u.fields.ptr[i];
            tree_put(d, "(pf ");
            tree_put_pos(d, field->pos);
            tree_put(d, " ");
            tree_put_name(d, field->name);
            tree_put(d, " ");
            tree_dump_pattern(d, field->pattern);
            tree_put(d, ") ");
        }
        tree_put(d, "]");
        return;
    }
}

static void tree_dump_pattern(TreeDump *d, const MsPattern *pattern) {
    if (pattern == NULL) {
        tree_put(d, "nil");
        return;
    }
    tree_put(d, "(pattern ");
    tree_put_pos(d, pattern->pos);
    tree_put(d, " ");
    tree_dump_pattern_fields(d, pattern);
    tree_put(d, ")");
}

/* ---- statements ---- */

typedef struct TreeStmtFields {
    const char *kind;
    const char *compound;
    const MsPattern *pattern;
    const MsTypeRef *type;
    const MsExpr *target;
    const MsExpr *value;
    MsStmts body;
    MsStmts else_body;
    MsStr name;
    MsPos group;
    bool is_mutable;
} TreeStmtFields;

static void tree_dump_stmt(TreeDump *d, const MsStmt *stmt);

static void tree_dump_body(TreeDump *d, MsStmts body) {
    tree_put(d, "[");
    for (uint32_t i = 0; i < body.len; i++) {
        tree_dump_stmt(d, body.ptr[i]);
        tree_put(d, " ");
    }
    tree_put(d, "]");
}

static TreeStmtFields tree_simple_stmt_fields(const TreeDump *d, const MsStmt *s) {
    TreeStmtFields f = {.compound = ""};
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND:
        f.kind = "bind";
        f.is_mutable = s->u.bind.is_mutable;
        f.group = s->u.bind.has_group ? s->u.bind.group : (MsPos){0};
        f.pattern = s->u.bind.pattern;
        f.type = s->u.bind.ty;
        f.value = s->u.bind.value;
        break;
    case MS_S_ASSIGN:
        f.kind = "assign";
        if (s->u.assign.has_compound) {
            f.compound = ms_binary_str((MsBinaryOp)s->u.assign.compound);
        }
        if (s->u.assign.member_target) {
            f.target = s->u.assign.target;
        } else {
            f.name = ms_name(d->names, s->u.assign.name);
        }
        f.value = s->u.assign.value;
        break;
    case MS_S_CALL:
        f.kind = "call";
        f.value = s->u.expr;
        break;
    case MS_S_RETURN:
        f.kind = "return";
        f.value = s->u.expr;
        break;
    case MS_S_BREAK:
        f.kind = "break";
        break;
    case MS_S_CONTINUE:
        f.kind = "continue";
        break;
    default:
        break;
    }
    return f;
}

static TreeStmtFields tree_block_stmt_fields(const TreeDump *d, const MsStmt *s) {
    TreeStmtFields f = {.compound = ""};
    switch ((MsStmtKind)s->kind) {
    case MS_S_IF:
        f.kind = "if";
        f.is_mutable = s->u.branch.is_mutable;
        f.pattern = s->u.branch.binding;
        f.value = s->u.branch.cond;
        f.body = s->u.branch.body;
        f.else_body = s->u.branch.else_body;
        break;
    case MS_S_WHILE:
        f.kind = "while";
        f.value = s->u.loop.cond;
        f.body = s->u.loop.body;
        break;
    case MS_S_FOR:
        f.kind = "for";
        f.name = ms_name(d->names, s->u.each.name);
        f.value = s->u.each.iter;
        f.body = s->u.each.body;
        break;
    default:
        break;
    }
    return f;
}

static bool tree_is_block_stmt(const MsStmt *s) {
    return s->kind == MS_S_IF || s->kind == MS_S_WHILE || s->kind == MS_S_FOR;
}

static void tree_dump_stmt(TreeDump *d, const MsStmt *stmt) {
    TreeStmtFields f = tree_is_block_stmt(stmt) ? tree_block_stmt_fields(d, stmt) : tree_simple_stmt_fields(d, stmt);
    tree_put(d, "(stmt ");
    tree_put_pos(d, stmt->pos);
    tree_put(d, " ");
    tree_put(d, f.kind);
    tree_put(d, " ");
    tree_put_quoted(d, f.name);
    tree_put(d, " ");
    tree_put_quoted_c(d, f.compound);
    tree_put(d, f.is_mutable ? " true " : " false ");
    tree_put_pos(d, f.group);
    tree_put(d, " ");
    tree_dump_pattern(d, f.pattern);
    tree_put(d, " ");
    tree_dump_type(d, f.type);
    tree_put(d, " ");
    tree_dump_expr(d, f.target);
    tree_put(d, " ");
    tree_dump_expr(d, f.value);
    tree_put(d, " ");
    tree_dump_body(d, f.body);
    tree_put(d, " ");
    tree_dump_body(d, f.else_body);
    tree_put(d, ")");
}

/* ---- declarations ---- */

typedef struct TreeDeclFields {
    const char *kind;
    const MsTypeRef *result;
    const MsTypeRef *contract;
    const MsTypeRef *receiver;
    const char *synthetic_result; /* name of a result type the parser never wrote, or NULL */
    MsCase **cases;
    MsMethod **methods;
    MsStmt **body;
    MsStr name;
    MsTypeParams type_params;
    MsParams fields;
    MsParams params;
    MsPos pos;
    MsPos synthetic_pos;
    uint32_t case_count;
    uint32_t method_count;
    uint32_t body_count;
    bool is_exported;
    bool is_constant;
    bool is_synthetic;
} TreeDeclFields;

static void tree_dump_type_params(TreeDump *d, MsTypeParams params) {
    tree_put(d, "[");
    for (uint32_t i = 0; i < params.len; i++) {
        const MsTypeParam *param = params.ptr[i];
        tree_put(d, "(tp ");
        tree_put_pos(d, param->pos);
        tree_put(d, " ");
        tree_put_name(d, param->name);
        tree_put(d, " ");
        tree_dump_types(d, param->bounds);
        tree_put(d, " ");
        tree_dump_type(d, param->def);
        tree_put(d, ") ");
    }
    tree_put(d, "]");
}

static void tree_dump_decl_fields(TreeDump *d, const TreeDeclFields *f);

static void tree_dump_method(TreeDump *d, const MsMethod *method) {
    TreeDeclFields f = {
        .kind = "fn",
        .pos = method->pos,
        .name = ms_name(d->names, method->func.name),
        .type_params = method->func.type_params,
        .params = method->func.params,
        .result = method->func.result,
        .body = method->func.body.ptr,
        .body_count = method->func.body.len,
    };
    tree_dump_decl_fields(d, &f);
}

static void tree_dump_cases(TreeDump *d, MsCase **cases, uint32_t count) {
    tree_put(d, " [");
    for (uint32_t i = 0; i < count; i++) {
        tree_put(d, "(case ");
        tree_put_pos(d, cases[i]->pos);
        tree_put(d, " ");
        tree_put_name(d, cases[i]->name);
        tree_put(d, " ");
        tree_dump_params(d, cases[i]->fields);
        tree_put(d, ") ");
    }
    tree_put(d, "] [");
}

static void tree_dump_decl_fields(TreeDump *d, const TreeDeclFields *f) {
    tree_put(d, "(decl ");
    tree_put_pos(d, f->pos);
    tree_put(d, " ");
    tree_put(d, f->kind);
    tree_put(d, " ");
    tree_put_quoted(d, f->name);
    tree_put(d, f->is_exported ? " true " : " false ");
    tree_put(d, f->is_constant ? "true " : "false ");
    tree_put_pos(d, (MsPos){0});
    tree_put(d, f->is_synthetic ? " true " : " false ");
    tree_dump_type_params(d, f->type_params);
    tree_put(d, " ");
    tree_dump_params(d, f->fields);
    tree_dump_cases(d, f->cases, f->case_count);
    for (uint32_t i = 0; i < f->method_count; i++) {
        tree_dump_method(d, f->methods[i]);
        tree_put(d, " ");
    }
    tree_put(d, "] ");
    tree_dump_params(d, f->params);
    tree_put(d, " ");
    if (f->synthetic_result != NULL) {
        tree_dump_synthetic_type(d, f->synthetic_pos, f->synthetic_result);
    } else {
        tree_dump_type(d, f->result);
    }
    tree_put(d, " ");
    tree_dump_type(d, f->contract);
    tree_put(d, " ");
    tree_dump_type(d, f->receiver);
    tree_put(d, " ");
    tree_dump_body(d, (MsStmts){.ptr = f->body, .len = f->body_count});
    tree_put(d, ")");
}

/* A constant dumps as a function whose body returns its value. */
static void tree_dump_constant(TreeDump *d, const MsDecl *decl) {
    MsStmt ret = {.pos = decl->u.konst.init_pos, .kind = MS_S_RETURN};
    ret.u.expr = decl->u.konst.value;
    MsStmt *body = &ret;
    TreeDeclFields f = {
        .kind = "fn",
        .pos = decl->pos,
        .name = ms_name(d->names, decl->u.konst.name),
        .is_exported = decl->is_exported,
        .is_constant = true,
        .is_synthetic = decl->synthetic,
        .result = decl->u.konst.ty,
        .body = &body,
        .body_count = 1,
    };
    if (decl->u.konst.ty == NULL) {
        f.synthetic_result = "";
        f.synthetic_pos = decl->u.konst.value->pos;
    }
    tree_dump_decl_fields(d, &f);
}

static void tree_dump_test(TreeDump *d, const MsDecl *decl) {
    TreeDeclFields f = {
        .kind = decl->u.test.bench ? "bench" : "test",
        .pos = decl->pos,
        .name = decl->u.test.name,
        .is_exported = decl->is_exported,
        .is_synthetic = decl->synthetic,
        .synthetic_result = "Void",
        .synthetic_pos = decl->pos,
        .body = decl->u.test.body.ptr,
        .body_count = decl->u.test.body.len,
    };
    tree_dump_decl_fields(d, &f);
}

static TreeDeclFields tree_type_decl_fields(const TreeDump *d, const MsDecl *x) {
    TreeDeclFields f = {.pos = x->pos, .is_exported = x->is_exported, .is_synthetic = x->synthetic};
    switch ((MsDeclKind)x->kind) {
    case MS_D_TYPE:
        f.kind = "type";
        f.name = ms_name(d->names, x->u.type.name);
        f.type_params = x->u.type.type_params;
        f.fields = x->u.type.fields;
        break;
    case MS_D_ENUM:
        f.kind = "alternative";
        f.name = ms_name(d->names, x->u.enumeration.name);
        f.type_params = x->u.enumeration.type_params;
        f.cases = x->u.enumeration.cases.ptr;
        f.case_count = x->u.enumeration.cases.len;
        break;
    case MS_D_ALIAS:
        f.kind = "alias";
        f.name = ms_name(d->names, x->u.alias.name);
        f.type_params = x->u.alias.type_params;
        break;
    default:
        break;
    }
    return f;
}

static TreeDeclFields tree_function_decl_fields(const TreeDump *d, const MsDecl *x) {
    TreeDeclFields f = {.pos = x->pos, .is_exported = x->is_exported, .is_synthetic = x->synthetic};
    switch ((MsDeclKind)x->kind) {
    case MS_D_FN:
        f.kind = x->u.fn.external ? "extern fn" : "fn";
        f.name = ms_name(d->names, x->u.fn.name);
        f.type_params = x->u.fn.type_params;
        f.params = x->u.fn.params;
        f.result = x->u.fn.result;
        f.body = x->u.fn.body.ptr;
        f.body_count = x->u.fn.body.len;
        break;
    case MS_D_INTERFACE:
        f.kind = "interface";
        f.name = ms_name(d->names, x->u.iface.name);
        f.type_params = x->u.iface.type_params;
        f.methods = x->u.iface.methods.ptr;
        f.method_count = x->u.iface.methods.len;
        break;
    case MS_D_IMPL:
        f.kind = "impl";
        f.methods = x->u.impl.methods.ptr;
        f.method_count = x->u.impl.methods.len;
        f.contract = x->u.impl.contract;
        f.receiver = x->u.impl.receiver;
        break;
    default:
        break;
    }
    return f;
}

static void tree_dump_decl(TreeDump *d, const MsDecl *decl) {
    TreeDeclFields f;
    switch ((MsDeclKind)decl->kind) {
    case MS_D_CONST:
        tree_dump_constant(d, decl);
        return;
    case MS_D_TEST:
        tree_dump_test(d, decl);
        return;
    case MS_D_TYPE:
    case MS_D_ENUM:
    case MS_D_ALIAS:
        f = tree_type_decl_fields(d, decl);
        break;
    case MS_D_FN:
    case MS_D_INTERFACE:
    case MS_D_IMPL:
        f = tree_function_decl_fields(d, decl);
        break;
    }
    tree_dump_decl_fields(d, &f);
}

void ms_dump_module(MsBuf *out, const MsNames *names, const MsModule *m) {
    TreeDump d = {.out = out, .names = names};
    for (uint32_t i = 0; i < m->nimports; i++) {
        const MsImport *import = &m->imports[i];
        tree_put(&d, "import ");
        tree_put_pos(&d, import->pos);
        tree_put(&d, " ");
        tree_put_pos(&d, import->name_pos);
        tree_put(&d, " ");
        tree_put_name(&d, import->name);
        tree_put(&d, " ");
        tree_put_quoted(&d, import->path);
        tree_put(&d, "\n");
    }
    for (uint32_t i = 0; i < m->ndecls; i++) {
        tree_dump_decl(&d, m->decls[i]);
        tree_put(&d, "\n");
    }
    tree_put(&d, "omitted [");
    for (uint32_t i = 0; i < m->nomitted; i++) {
        tree_put_quoted(&d, m->omitted[i]);
        tree_put(&d, " ");
    }
    tree_put(&d, "]\nrecovered [");
    for (uint32_t i = 0; i < m->nrecovered; i++) {
        ms_buf_printf(out, "%u-%u ", m->recovered[i].start, m->recovered[i].end);
    }
    tree_put(&d, "]\n");
}
