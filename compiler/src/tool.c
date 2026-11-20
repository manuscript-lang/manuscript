/* The tool interface (include/ms/tool.h): flat tables for Manuscript programs. */
#include "libms.c"
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"
#include "ms/parse.h"
#include "ms/tool.h"

static void push_int(ms_list *out, int64_t v) {
    ms_value value;
    memset(&value, 0, sizeof value);
    value.kind = MS_INT;
    value.as.i = v;
    ms_list_push(out, &value);
}

uint8_t ms_tool_lex(const ms_str *text, ms_list *out, int64_t *code_out, ms_str *message_out) {
    MsArena arena = {0};
    MsLexed lexed;
    MsDiag diag;
    const char *src = (const char *)ms_str_data(text);
    size_t len = ms_str_len(text);
    if (!ms_utf8_valid(src, len)) {
        static const char msg[] = "invalid UTF-8";
        ms_string_new((const uint8_t *)msg, sizeof msg - 1, message_out);
        *code_out = 0;
        return 1;
    }
    if (!ms_lex(&arena, src, len, &lexed, &diag)) {
        ms_string_new((const uint8_t *)diag.message.ptr, diag.message.len, message_out);
        *code_out = diag.pos.offset;
        ms_arena_free(&arena);
        return 1;
    }
    for (size_t i = 0; i < lexed.ntokens; i++) {
        const MsToken *t = &lexed.tokens[i];
        push_int(out, t->kind);
        push_int(out, t->lo);
        push_int(out, t->hi);
        push_int(out, t->pos.offset);
        push_int(out, t->pos.line);
        push_int(out, t->pos.column);
        push_int(out, t->end.offset);
        push_int(out, t->end.line);
        push_int(out, t->end.column);
    }
    ms_arena_free(&arena);
    return 0;
}

void ms_tool_token_kinds(ms_list *out) {
    for (int k = 0; k < MS_T_COUNT; k++) {
        const char *s = ms_tok_str((MsTok)k);
        ms_value value;
        memset(&value, 0, sizeof value);
        value.kind = MS_STRING;
        value.as.buf.data = (const uint8_t *)s;
        value.as.buf.len = strlen(s);
        ms_list_push(out, &value);
    }
}

/* ---- syntax trees ---- */

#define NODE_KINDS(X)                                                                              \
    X(None) X(List) X(Pos) X(Module) X(Import) X(Fn) X(Const) X(Type) X(Enum) X(Alias)             \
    X(Interface) X(Impl) X(Test) X(Method) X(Case) X(Param) X(TypeParam) X(TypeNamed) X(TypeFn)    \
    X(Number) X(Bool) X(Void) X(Text) X(TextPart) X(Name) X(Member) X(Apply) X(Index) X(Probe)     \
    X(ListExpr) X(Map) X(MapEntry) X(Unary) X(Binary) X(Lambda) X(Call) X(Arg) X(Match) X(Arm)     \
    X(ArmBinding) X(PatName) X(PatList) X(PatType) X(PatField) X(Bind) X(Assign) X(CallStmt)       \
    X(Return) X(Break) X(Continue) X(If) X(While) X(For)

enum {
#define X(n) N_##n,
    NODE_KINDS(X)
#undef X
};

static const char *const node_kind_names[] = {
#define X(n) #n,
    NODE_KINDS(X)
#undef X
};

typedef struct Tree {
    MsArena arena;
    MsNames names;
    MsModule module;
    bool ok;
    MsDiag diag;
    MsBuf nodes; /* int64_t records */
    char *text;
} Tree;

static void tree_drop(void *payload) {
    Tree *t = payload;
    ms_buf_free(&t->nodes);
    ms_names_free(&t->names);
    ms_arena_free(&t->arena);
    free(t->text);
}

typedef struct Enc {
    MsBuf *out;
    MsNames *names;
} Enc;

static int64_t sym_of(Enc *e, MsStr s) { return ms_intern(e->names, s.ptr, s.len); }

/* Writes one record and returns its index in the table so the caller can patch the child count. */
static size_t rec(Enc *e, int kind, uint32_t id, MsPos pos, MsPos end, int64_t flags, int64_t a, int64_t b) {
    size_t at = e->out->len / sizeof(int64_t) / MS_TOOL_NODE_WIDTH;
    int64_t *r = ms_buf_push(e->out, sizeof(int64_t) * MS_TOOL_NODE_WIDTH);
    r[0] = kind;
    r[1] = id;
    r[2] = pos.offset;
    r[3] = pos.line;
    r[4] = pos.column;
    r[5] = end.offset;
    r[6] = end.line;
    r[7] = end.column;
    r[8] = flags;
    r[9] = a;
    r[10] = b;
    r[11] = 0;
    return at;
}

static const MsPos NOPOS = {0, 0, 0};

/* Child bookkeeping: `open` records a node, `close` sets its child count from the number of direct
 * children written since. Children are counted by the caller incrementing `*kids`. */
#define KID(kids) ((*(kids))++)

static void enc_expr(Enc *e, const MsExpr *x, int *kids);
static void enc_type(Enc *e, const MsTypeRef *t, int *kids);
static void enc_stmt(Enc *e, const MsStmt *s, int *kids);
static void enc_pattern(Enc *e, const MsPattern *p, int *kids);

static void put_none(Enc *e, int *kids) {
    rec(e, N_None, 0, NOPOS, NOPOS, 0, -1, -1);
    KID(kids);
}

static void patch(Enc *e, size_t at, int kids) { ((int64_t *)e->out->data)[at * MS_TOOL_NODE_WIDTH + 11] = kids; }

static size_t list_open(Enc *e, int *kids) {
    size_t at = rec(e, N_List, 0, NOPOS, NOPOS, 0, -1, -1);
    KID(kids);
    return at;
}

static void enc_types(Enc *e, MsTypeRef *const *ts, uint32_t n, int *kids) {
    size_t at = list_open(e, kids);
    int k = 0;
    for (uint32_t i = 0; i < n; i++) enc_type(e, ts[i], &k);
    patch(e, at, k);
}

static void enc_param(Enc *e, const MsParam *p, int *kids) {
    size_t at = rec(e, N_Param, p->id, p->pos, NOPOS, (p->mutable_ ? 1 : 0) | (p->moving ? 2 : 0), p->name, -1);
    KID(kids);
    int k = 0;
    enc_type(e, p->ty, &k);
    enc_expr(e, p->def, &k);
    patch(e, at, k);
}

static void enc_params(Enc *e, MsParam *const *ps, uint32_t n, int *kids) {
    size_t at = list_open(e, kids);
    int k = 0;
    for (uint32_t i = 0; i < n; i++) enc_param(e, ps[i], &k);
    patch(e, at, k);
}

static void enc_type_params(Enc *e, MsTypeParams tps, int *kids) {
    size_t at = list_open(e, kids);
    int k = 0;
    for (uint32_t i = 0; i < tps.len; i++) {
        const MsTypeParam *tp = tps.ptr[i];
        size_t tat = rec(e, N_TypeParam, tp->id, tp->pos, NOPOS, 0, tp->name, -1);
        KID(&k);
        int tk = 0;
        enc_types(e, tp->bounds.ptr, tp->bounds.len, &tk);
        enc_type(e, tp->def, &tk);
        patch(e, tat, tk);
    }
    patch(e, at, k);
}

static void enc_type(Enc *e, const MsTypeRef *t, int *kids) {
    if (t == NULL) {
        put_none(e, kids);
        return;
    }
    if (t->kind == MS_TYPE_NAMED) {
        size_t at = rec(e, N_TypeNamed, t->id, t->pos, NOPOS, 0, t->name, -1);
        KID(kids);
        int k = 0;
        enc_types(e, t->args.ptr, t->args.len, &k);
        patch(e, at, k);
    } else {
        size_t at = rec(e, N_TypeFn, t->id, t->pos, NOPOS, 0, -1, -1);
        KID(kids);
        int k = 0;
        enc_params(e, t->params.ptr, t->params.len, &k);
        enc_type(e, t->result, &k);
        patch(e, at, k);
    }
}

static void enc_body(Enc *e, MsStmt *const *b, uint32_t n, int *kids) {
    size_t at = list_open(e, kids);
    int k = 0;
    for (uint32_t i = 0; i < n; i++) enc_stmt(e, b[i], &k);
    patch(e, at, k);
}

static void enc_pattern(Enc *e, const MsPattern *p, int *kids) {
    if (p == NULL) {
        put_none(e, kids);
        return;
    }
    if (p->kind == MS_P_NAME) {
        rec(e, N_PatName, p->id, p->pos, NOPOS, 0, p->u.name, -1);
        KID(kids);
    } else if (p->kind == MS_P_LIST) {
        size_t at = rec(e, N_PatList, p->id, p->pos, NOPOS, 0, -1, -1);
        KID(kids);
        int k = 0;
        for (uint32_t i = 0; i < p->u.list.len; i++) enc_pattern(e, p->u.list.ptr[i], &k);
        patch(e, at, k);
    } else {
        size_t at = rec(e, N_PatType, p->id, p->pos, NOPOS, 0, -1, -1);
        KID(kids);
        int k = 0;
        for (uint32_t i = 0; i < p->u.fields.len; i++) {
            const MsPatternField *f = &p->u.fields.ptr[i];
            size_t fat = rec(e, N_PatField, 0, f->pos, NOPOS, 0, f->name, -1);
            KID(&k);
            int fk = 0;
            enc_pattern(e, f->pattern, &fk);
            patch(e, fat, fk);
        }
        patch(e, at, k);
    }
}

static void enc_expr(Enc *e, const MsExpr *x, int *kids) {
    if (x == NULL) {
        put_none(e, kids);
        return;
    }
    size_t at;
    int k = 0;
#define OPEN(kind, flags, a, b) (at = rec(e, kind, x->id, x->pos, x->end, flags, a, b), KID(kids))
    switch (x->kind) {
    case MS_E_NUMBER: OPEN(N_Number, 0, x->u.sym, -1); break;
    case MS_E_BOOL: OPEN(N_Bool, x->u.flag ? 1 : 0, -1, -1); break;
    case MS_E_VOID: OPEN(N_Void, 0, -1, -1); break;
    case MS_E_NAME: OPEN(N_Name, 0, x->u.sym, -1); break;
    case MS_E_TEXT:
        OPEN(N_Text, 0, -1, -1);
        for (uint32_t i = 0; i < x->u.text.len; i++) {
            const MsTextPart *part = &x->u.text.ptr[i];
            size_t pat = rec(e, N_TextPart, 0, NOPOS, NOPOS, part->expr ? 1 : 0, part->expr ? -1 : sym_of(e, part->lit), -1);
            KID(&k);
            int pk = 0;
            if (part->expr) enc_expr(e, part->expr, &pk);
            patch(e, pat, pk);
        }
        patch(e, at, k);
        break;
    case MS_E_MEMBER:
        OPEN(N_Member, 0, x->u.member.name, -1);
        enc_expr(e, x->u.member.left, &k);
        patch(e, at, k);
        break;
    case MS_E_APPLY:
        OPEN(N_Apply, 0, -1, -1);
        enc_expr(e, x->u.apply.left, &k);
        enc_types(e, x->u.apply.types.ptr, x->u.apply.types.len, &k);
        enc_expr(e, x->u.apply.value, &k);
        patch(e, at, k);
        break;
    case MS_E_INDEX:
        OPEN(N_Index, 0, -1, -1);
        enc_expr(e, x->u.bin.left, &k);
        enc_expr(e, x->u.bin.right, &k);
        patch(e, at, k);
        break;
    case MS_E_PROBE:
        OPEN(N_Probe, 0, -1, -1);
        enc_expr(e, x->u.bin.left, &k);
        patch(e, at, k);
        break;
    case MS_E_LIST:
        OPEN(N_ListExpr, 0, -1, -1);
        for (uint32_t i = 0; i < x->u.list.len; i++) enc_expr(e, x->u.list.ptr[i], &k);
        patch(e, at, k);
        break;
    case MS_E_MAP:
        OPEN(N_Map, 0, -1, -1);
        for (uint32_t i = 0; i < x->u.map.len; i++) {
            size_t eat = rec(e, N_MapEntry, 0, NOPOS, NOPOS, 0, -1, -1);
            KID(&k);
            int ek = 0;
            enc_expr(e, x->u.map.ptr[i].key, &ek);
            enc_expr(e, x->u.map.ptr[i].value, &ek);
            patch(e, eat, ek);
        }
        patch(e, at, k);
        break;
    case MS_E_UNARY:
        OPEN(N_Unary, x->op, -1, -1);
        enc_expr(e, x->u.bin.left, &k);
        patch(e, at, k);
        break;
    case MS_E_BINARY:
        OPEN(N_Binary, x->op, -1, -1);
        enc_expr(e, x->u.bin.left, &k);
        enc_expr(e, x->u.bin.right, &k);
        patch(e, at, k);
        break;
    case MS_E_LAMBDA:
        OPEN(N_Lambda, 0, -1, -1);
        enc_params(e, x->u.lambda.params.ptr, x->u.lambda.params.len, &k);
        enc_type(e, x->u.lambda.result, &k);
        enc_body(e, x->u.lambda.body.ptr, x->u.lambda.body.len, &k);
        patch(e, at, k);
        break;
    case MS_E_CALL: {
        OPEN(N_Call, 0, -1, -1);
        enc_expr(e, x->u.call.callee, &k);
        size_t lat = list_open(e, &k);
        int lk = 0;
        for (uint32_t i = 0; i < x->u.call.args.len; i++) {
            const MsArg *a = &x->u.call.args.ptr[i];
            size_t aat = rec(e, N_Arg, 0, a->pos, NOPOS, a->has_name ? 1 : 0, a->has_name ? (int64_t)a->name : -1, -1);
            KID(&lk);
            int ak = 0;
            enc_expr(e, a->value, &ak);
            patch(e, aat, ak);
        }
        patch(e, lat, lk);
        patch(e, at, k);
        break;
    }
    default: {
        OPEN(N_Match, 0, -1, -1);
        enc_expr(e, x->u.match.scrutinee, &k);
        size_t lat = list_open(e, &k);
        int lk = 0;
        for (uint32_t i = 0; i < x->u.match.arms.len; i++) {
            const MsArm *a = x->u.match.arms.ptr[i];
            size_t aat = rec(e, N_Arm, a->id, a->pos, NOPOS, (a->from_if ? 1 : 0) | (a->bare ? 2 : 0), -1, -1);
            KID(&lk);
            int ak = 0;
            enc_expr(e, a->path, &ak);
            size_t bat = list_open(e, &ak);
            int bk = 0;
            for (uint32_t j = 0; j < a->bindings.len; j++) {
                rec(e, N_ArmBinding, 0, a->bindings.ptr[j].pos, NOPOS, 0, a->bindings.ptr[j].name, -1);
                KID(&bk);
            }
            patch(e, bat, bk);
            enc_body(e, a->body.ptr, a->body.len, &ak);
            enc_expr(e, a->value, &ak);
            patch(e, aat, ak);
        }
        patch(e, lat, lk);
        patch(e, at, k);
        break;
    }
    }
#undef OPEN
}

static void enc_stmt(Enc *e, const MsStmt *s, int *kids) {
    size_t at;
    int k = 0;
#define OPEN(kind, flags, a, b) (at = rec(e, kind, s->id, s->pos, NOPOS, flags, a, b), KID(kids))
    switch (s->kind) {
    case MS_S_BIND:
        OPEN(N_Bind, (s->u.bind.mutable_ ? 1 : 0) | (s->u.bind.has_group ? 2 : 0), -1, -1);
        if (s->u.bind.has_group) {
            int64_t *r = (int64_t *)e->out->data + at * MS_TOOL_NODE_WIDTH;
            r[5] = s->u.bind.group.offset;
            r[6] = s->u.bind.group.line;
            r[7] = s->u.bind.group.column;
        }
        enc_pattern(e, s->u.bind.pattern, &k);
        enc_type(e, s->u.bind.ty, &k);
        enc_expr(e, s->u.bind.value, &k);
        break;
    case MS_S_ASSIGN:
        OPEN(N_Assign,
             (s->u.assign.member_target ? 1 : 0) | (s->u.assign.has_compound ? 2 : 0) | ((int64_t)s->u.assign.compound << 8),
             s->u.assign.member_target ? -1 : (int64_t)s->u.assign.name, -1);
        enc_expr(e, s->u.assign.member_target ? s->u.assign.target : NULL, &k);
        enc_expr(e, s->u.assign.value, &k);
        break;
    case MS_S_CALL:
        OPEN(N_CallStmt, 0, -1, -1);
        enc_expr(e, s->u.expr, &k);
        break;
    case MS_S_RETURN:
        OPEN(N_Return, 0, -1, -1);
        enc_expr(e, s->u.expr, &k);
        break;
    case MS_S_BREAK: OPEN(N_Break, 0, -1, -1); break;
    case MS_S_CONTINUE: OPEN(N_Continue, 0, -1, -1); break;
    case MS_S_IF:
        OPEN(N_If, s->u.if_.mutable_ ? 1 : 0, -1, -1);
        enc_pattern(e, s->u.if_.binding, &k);
        enc_expr(e, s->u.if_.cond, &k);
        enc_body(e, s->u.if_.body.ptr, s->u.if_.body.len, &k);
        enc_body(e, s->u.if_.else_body.ptr, s->u.if_.else_body.len, &k);
        break;
    case MS_S_WHILE:
        OPEN(N_While, 0, -1, -1);
        enc_expr(e, s->u.while_.cond, &k);
        enc_body(e, s->u.while_.body.ptr, s->u.while_.body.len, &k);
        break;
    default:
        OPEN(N_For, 0, s->u.for_.name, -1);
        enc_expr(e, s->u.for_.iter, &k);
        enc_body(e, s->u.for_.body.ptr, s->u.for_.body.len, &k);
        break;
    }
    patch(e, at, k);
#undef OPEN
}

static void pos_leaf(Enc *e, MsPos p, int *kids) {
    rec(e, N_Pos, 0, p, NOPOS, 0, -1, -1);
    KID(kids);
}

static void enc_func_kids(Enc *e, const MsFunc *f, int *k) {
    enc_type_params(e, f->type_params, k);
    enc_params(e, f->params.ptr, f->params.len, k);
    enc_type(e, f->result, k);
    enc_body(e, f->body.ptr, f->body.len, k);
}

static void enc_methods(Enc *e, MsMethod **ms, uint32_t n, int *kids) {
    size_t lat = list_open(e, kids);
    int lk = 0;
    for (uint32_t i = 0; i < n; i++) {
        const MsMethod *m = ms[i];
        size_t at = rec(e, N_Method, m->id, m->pos, NOPOS,
                        (m->mutating ? 1 : 0) | (m->consuming ? 2 : 0) | (m->func.external ? 4 : 0), m->func.name, -1);
        KID(&lk);
        int k = 0;
        pos_leaf(e, m->var_at, &k);
        enc_types(e, m->receiver_args.ptr, m->receiver_args.len, &k);
        enc_func_kids(e, &m->func, &k);
        patch(e, at, k);
    }
    patch(e, lat, lk);
}

static void enc_decl(Enc *e, const MsDecl *d, int *kids) {
    int64_t base = (d->export_ ? 1 : 0) | (d->synthetic ? 2 : 0);
    size_t at;
    int k = 0;
#define OPEN(kind, flags, a, b) (at = rec(e, kind, d->id, d->pos, NOPOS, base | (flags), a, b), KID(kids))
    switch (d->kind) {
    case MS_D_FN:
        OPEN(N_Fn, d->u.fn.external ? 4 : 0, d->u.fn.name, -1);
        enc_func_kids(e, &d->u.fn, &k);
        break;
    case MS_D_CONST:
        OPEN(N_Const, 0, d->u.konst.name, -1);
        enc_type(e, d->u.konst.ty, &k);
        enc_expr(e, d->u.konst.value, &k);
        pos_leaf(e, d->u.konst.init_pos, &k);
        break;
    case MS_D_TYPE:
        OPEN(N_Type, (d->u.type.external ? 4 : 0) | (d->u.type.opaque ? 8 : 0), d->u.type.name, -1);
        enc_type_params(e, d->u.type.type_params, &k);
        enc_params(e, d->u.type.fields.ptr, d->u.type.fields.len, &k);
        break;
    case MS_D_ENUM: {
        OPEN(N_Enum, d->u.enum_.opaque ? 8 : 0, d->u.enum_.name, -1);
        enc_type_params(e, d->u.enum_.type_params, &k);
        size_t lat = list_open(e, &k);
        int lk = 0;
        for (uint32_t i = 0; i < d->u.enum_.cases.len; i++) {
            const MsCase *c = d->u.enum_.cases.ptr[i];
            size_t cat = rec(e, N_Case, c->id, c->pos, NOPOS, 0, c->name, -1);
            KID(&lk);
            int ck = 0;
            enc_params(e, c->fields.ptr, c->fields.len, &ck);
            patch(e, cat, ck);
        }
        patch(e, lat, lk);
        break;
    }
    case MS_D_ALIAS:
        OPEN(N_Alias, 0, d->u.alias.name, -1);
        enc_type_params(e, d->u.alias.type_params, &k);
        enc_types(e, d->u.alias.targets.ptr, d->u.alias.targets.len, &k);
        break;
    case MS_D_INTERFACE:
        OPEN(N_Interface, 0, d->u.iface.name, -1);
        enc_type_params(e, d->u.iface.type_params, &k);
        enc_methods(e, d->u.iface.methods.ptr, d->u.iface.methods.len, &k);
        break;
    case MS_D_IMPL:
        OPEN(N_Impl, 0, -1, -1);
        enc_type(e, d->u.impl.contract, &k);
        enc_type(e, d->u.impl.receiver, &k);
        enc_type_params(e, d->u.impl.bounds, &k);
        enc_methods(e, d->u.impl.methods.ptr, d->u.impl.methods.len, &k);
        break;
    default:
        OPEN(N_Test, d->u.test.bench ? 16 : 0, sym_of(e, d->u.test.name), d->u.test.per);
        enc_body(e, d->u.test.body.ptr, d->u.test.body.len, &k);
        break;
    }
    patch(e, at, k);
#undef OPEN
}

static void enc_module(Tree *t) {
    Enc enc = {&t->nodes, &t->names};
    Enc *e = &enc;
    const MsModule *m = &t->module;
    size_t at = rec(e, N_Module, 0, NOPOS, NOPOS, 0, m->nimports, m->node_count);
    int k = 0;
    for (uint32_t i = 0; i < m->nimports; i++) {
        const MsImport *im = &m->imports[i];
        size_t iat = rec(e, N_Import, im->id, im->pos, NOPOS, 0, im->name, sym_of(e, im->path));
        k++;
        int ik = 0;
        pos_leaf(e, im->clause, &ik);
        pos_leaf(e, im->name_pos, &ik);
        patch(e, iat, ik);
    }
    for (uint32_t i = 0; i < m->ndecls; i++) enc_decl(e, m->decls[i], &k);
    patch(e, at, k);
}

ms_object *ms_tool_parse(const ms_str *text) {
    ms_object *obj = ms_object_new(sizeof(Tree), tree_drop);
    Tree *t = ms_payload(obj);
    size_t len = ms_str_len(text);
    t->text = malloc(len + 1);
    memcpy(t->text, ms_str_data(text), len);
    t->text[len] = 0;
    ms_names_init(&t->names);
    if (!ms_utf8_valid(t->text, len)) {
        t->diag.message = (MsStr){"invalid UTF-8", 13};
        return obj;
    }
    if (!ms_parse(&t->arena, &t->names, t->text, len, &t->module, &t->diag)) return obj;
    t->ok = true;
    enc_module(t);
    return obj;
}

void ms_tool_tree_error(ms_object *tree, ms_str *out) {
    Tree *t = ms_payload(tree);
    if (t->ok) return;
    ms_string_new((const uint8_t *)t->diag.message.ptr, t->diag.message.len, out);
}

int64_t ms_tool_tree_error_offset(ms_object *tree) { Tree *t = ms_payload(tree); return t->ok ? 0 : t->diag.pos.offset; }
int64_t ms_tool_tree_error_line(ms_object *tree) { Tree *t = ms_payload(tree); return t->ok ? 0 : t->diag.pos.line; }
int64_t ms_tool_tree_error_column(ms_object *tree) { Tree *t = ms_payload(tree); return t->ok ? 0 : t->diag.pos.column; }

void ms_tool_tree_nodes(ms_object *tree, ms_list *out) {
    Tree *t = ms_payload(tree);
    const int64_t *r = (const int64_t *)t->nodes.data;
    size_t n = t->nodes.len / sizeof(int64_t);
    for (size_t i = 0; i < n; i++) push_int(out, r[i]);
}

void ms_tool_tree_names(ms_object *tree, ms_list *out) {
    Tree *t = ms_payload(tree);
    for (uint32_t i = 0; i < t->names.count; i++) {
        ms_value value;
        memset(&value, 0, sizeof value);
        value.kind = MS_STRING;
        value.as.buf.data = (const uint8_t *)t->names.text[i];
        value.as.buf.len = t->names.len[i];
        ms_list_push(out, &value);
    }
}

void ms_tool_node_kinds(ms_list *out) {
    for (size_t i = 0; i < sizeof node_kind_names / sizeof *node_kind_names; i++) {
        ms_value value;
        memset(&value, 0, sizeof value);
        value.kind = MS_STRING;
        value.as.buf.data = (const uint8_t *)node_kind_names[i];
        value.as.buf.len = strlen(node_kind_names[i]);
        ms_list_push(out, &value);
    }
}
