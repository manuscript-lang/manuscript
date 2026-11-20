/* The tool interface (include/ms/tool.h): flat tables for Manuscript programs. */
#include <stdlib.h>
#include <string.h>

#include "ms/diag.h"
#include "ms/format.h"
#include "ms/lex.h"
#include "ms/packages.h"
#include "ms/parse.h"
#include "ms/project.h"
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

/* Reports a syntax error in the header form of ms_tool_format. */
static void format_failure(const char *code, const MsDiag *diag, int64_t offset, int64_t *code_out,
                           ms_str *message_out) {
    MsBuf text = {0};
    ms_buf_printf(&text, "%s\t%lld\t%lld\t", code, (long long)diag->pos.line, (long long)diag->pos.column);
    ms_buf_put(&text, diag->message.ptr, diag->message.len);
    ms_string_new((const uint8_t *)text.data, text.len, message_out);
    ms_buf_free(&text);
    *code_out = offset;
}

uint8_t ms_tool_format(const ms_str *text, ms_str *out, int64_t *code_out, ms_str *message_out) {
    MsArena arena = {0};
    MsBuf formatted = {0};
    MsDiag diag;
    const char *src = (const char *)ms_str_data(text);
    size_t len = ms_str_len(text);
    if (!ms_utf8_valid(src, len)) {
        MsDiag invalid = {.pos = {.offset = 0, .line = 1, .column = 1}, .message = {"invalid UTF-8", 13}};
        format_failure(ms_code_for("parse", invalid.message), &invalid, 0, code_out, message_out);
        return 1;
    }
    if (!ms_format(&arena, src, len, &formatted, &diag)) {
        format_failure(ms_code_for("parse", diag.message), &diag, diag.pos.offset, code_out, message_out);
        ms_buf_free(&formatted);
        ms_arena_free(&arena);
        return 1;
    }
    ms_string_new((const uint8_t *)formatted.data, formatted.len, out);
    ms_buf_free(&formatted);
    ms_arena_free(&arena);
    return 0;
}

void ms_tool_lex_blocks(const ms_str *text, ms_list *out) {
    MsArena arena = {0};
    MsLexed lexed;
    MsDiag diag;
    const char *src = (const char *)ms_str_data(text);
    size_t len = ms_str_len(text);
    if (ms_utf8_valid(src, len) && ms_lex(&arena, src, len, &lexed, &diag)) {
        for (size_t i = 0; i < lexed.nblocks; i++) {
            push_int(out, (int64_t)lexed.blocks[i].start);
            push_int(out, (int64_t)lexed.blocks[i].end);
        }
    }
    ms_arena_free(&arena);
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

static void push_text(ms_list *out, const char *text) {
    ms_value value;
    memset(&value, 0, sizeof value);
    value.kind = MS_STRING;
    value.as.buf.data = (const uint8_t *)text;
    value.as.buf.len = strlen(text);
    ms_list_push(out, &value);
}

uint8_t ms_tool_dependencies(const ms_str *manifest, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    const char *path = ms_arena_strndup(&arena, (const char *)ms_str_data(manifest), ms_str_len(manifest));
    MsProject project;
    MsProjectError error = {0};
    uint8_t status = 0;
    if (!ms_project_read(&arena, path, &project, &error)) {
        const char *text = ms_project_error_text(&arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = ms_project_error_is_unsupported(&error) ? 2 : 1;
    }
    for (uint32_t i = 0; status == 0 && i < project.dependency_count; i++) {
        push_text(out, ms_project_dependency_row(&arena, &project.dependencies[i]));
    }
    ms_arena_free(&arena);
    return status;
}

/* One row of `ms_tool_project`: its kind, then its fields, separated by tabs. */
static void push_row(MsArena *a, ms_list *out, const char *kind, const char *first, const char *second) {
    if (first == NULL) {
        push_text(out, kind);
    } else if (second == NULL) {
        push_text(out, ms_arena_fmt(a, "%s\t%s", kind, first).ptr);
    } else {
        push_text(out, ms_arena_fmt(a, "%s\t%s\t%s", kind, first, second).ptr);
    }
}

static void push_aliases(MsArena *a, ms_list *out, const char *kind, const MsAlias *aliases, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        push_row(a, out, kind, aliases[i].name, aliases[i].target);
    }
}

uint8_t ms_tool_project(const ms_str *manifest, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    const char *path = ms_arena_strndup(&arena, (const char *)ms_str_data(manifest), ms_str_len(manifest));
    MsProject p;
    MsProjectError error = {0};
    uint8_t status = 0;
    if (!ms_project_read(&arena, path, &p, &error)) {
        const char *text = ms_project_error_text(&arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = ms_project_error_is_unsupported(&error) ? 2 : 1;
    } else {
        push_row(&arena, out, "root", p.root, NULL);
        push_row(&arena, out, "file", p.file, NULL);
        push_row(&arena, out, "name", p.name, NULL);
        push_row(&arena, out, "source", p.source, NULL);
        push_row(&arena, out, "entry", p.entry, NULL);
        if (p.has_version) {
            push_row(&arena, out, "version", ms_version_text(&arena, &p.version), NULL);
        }
        push_aliases(&arena, out, "alias", p.aliases, p.alias_count);
        push_aliases(&arena, out, "embed", p.embed, p.embed_count);
        push_aliases(&arena, out, "path", p.path_dependencies, p.path_dependency_count);
        for (uint32_t i = 0; i < p.dependency_count; i++) {
            push_row(&arena, out, "dep", ms_project_dependency_row(&arena, &p.dependencies[i]), NULL);
        }
        for (uint32_t i = 0; i < p.allowed_effect_count; i++) {
            const MsEffectRule *rule = &p.allowed_effects[i];
            MsBuf patterns = {0};
            for (uint32_t k = 0; k < rule->count; k++) {
                ms_buf_printf(&patterns, "%s%s", k > 0 ? "\t" : "", rule->patterns[k]);
            }
            push_row(&arena, out, "allow", rule->name, ms_arena_strndup(&arena, patterns.data == NULL ? "" : patterns.data, patterns.len));
            ms_buf_free(&patterns);
        }
        for (uint32_t i = 0; i < p.effect_count; i++) {
            push_row(&arena, out, "effect", p.effects[i], NULL);
        }
        if (p.is_workspace) {
            push_row(&arena, out, "workspace", NULL, NULL);
        }
        for (uint32_t i = 0; i < p.member_count; i++) {
            push_row(&arena, out, "member", p.members[i], NULL);
        }
    }
    ms_arena_free(&arena);
    return status;
}

uint8_t ms_tool_discover(const ms_str *target, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    const char *path = ms_arena_strndup(&arena, (const char *)ms_str_data(target), ms_str_len(target));
    const char **files = NULL;
    uint32_t count = 0;
    MsProjectError error = {0};
    uint8_t status = 0;
    if (!ms_project_format_paths(&arena, path, &files, &count, &error)) {
        const char *text = ms_project_error_text(&arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = ms_project_error_is_unsupported(&error) ? 2 : 1;
    }
    for (uint32_t i = 0; status == 0 && i < count; i++) {
        push_text(out, files[i]);
    }
    ms_arena_free(&arena);
    return status;
}

static const char *install_state_name(MsInstallState state) {
    switch (state) {
    case MS_INSTALL_FETCHED: return "fetched";
    case MS_INSTALL_CACHED: return "cached";
    case MS_INSTALL_KEPT: return "kept";
    }
    return "";
}

uint8_t ms_tool_install(const ms_str *manifest, const ms_list *update, uint8_t locked, uint8_t frozen, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    const size_t update_count = ms_list_len(update);
    const char **names = MS_NEW_N(&arena, const char *, update_count + 1);
    for (size_t i = 0; i < update_count; i++) {
        ms_value value = ms_list_get(update, i);
        names[i] = ms_arena_strndup(&arena, (const char *)value.as.buf.data, value.as.buf.len);
        ms_value_free(&value);
    }
    const MsInstallOptions options = {.manifest = ms_arena_strndup(&arena, (const char *)ms_str_data(manifest), ms_str_len(manifest)),
                                      .update = names, .update_count = (uint32_t)update_count, .locked = locked != 0, .frozen = frozen != 0};
    MsInstallReport report = {0};
    MsProjectError error = {0};
    uint8_t status = 0;
    if (!ms_install(&arena, &options, &report, &error)) {
        const char *text = ms_project_error_text(&arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = ms_project_error_is_unsupported(&error) ? 2 : 1;
    }
    for (uint32_t i = 0; status == 0 && i < report.count; i++) {
        const MsInstalledCopy *c = &report.copies[i];
        push_text(out, ms_arena_fmt(&arena, "%s\t%s\t%s\t%s\t%s", c->name, c->copy.entry.spec, c->copy.entry.revision,
                                   install_state_name(c->state), c->effects).ptr);
    }
    ms_arena_free(&arena);
    return status;
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

/* The node table is a byte buffer, so a field is moved with memcpy rather than a pointer cast. */
static void field_store(MsBuf *table, size_t index, int64_t value) {
    memcpy(table->data + index * sizeof value, &value, sizeof value);
}

static int64_t field_load(const MsBuf *table, size_t index) {
    int64_t value;
    memcpy(&value, table->data + index * sizeof value, sizeof value);
    return value;
}

static void patch(Enc *e, size_t at, int kids) { field_store(e->out, at * MS_TOOL_NODE_WIDTH + 11, kids); }

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
    size_t at = rec(e, N_Param, p->id, p->pos, NOPOS, (p->is_mutable ? 1 : 0) | (p->moving ? 2 : 0), p->name, -1);
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

/* Records the expression's own node and counts it as a child of the caller. */
static size_t open_expr(Enc *e, const MsExpr *x, int kind, int flags, int64_t a, int64_t b, int *kids) {
    const size_t at = rec(e, kind, x->id, x->pos, x->end, flags, a, b);
    KID(kids);
    return at;
}

static void enc_text(Enc *e, const MsExpr *x, int *kids) {
    const size_t at = open_expr(e, x, N_Text, 0, -1, -1, kids);
    int k = 0;
    for (uint32_t i = 0; i < x->u.text.len; i++) {
        const MsTextPart *part = &x->u.text.ptr[i];
        const size_t part_at =
            rec(e, N_TextPart, 0, NOPOS, NOPOS, part->expr ? 1 : 0, part->expr ? -1 : sym_of(e, part->lit), -1);
        KID(&k);
        int part_kids = 0;
        if (part->expr) enc_expr(e, part->expr, &part_kids);
        patch(e, part_at, part_kids);
    }
    patch(e, at, k);
}

static void enc_map(Enc *e, const MsExpr *x, int *kids) {
    const size_t at = open_expr(e, x, N_Map, 0, -1, -1, kids);
    int k = 0;
    for (uint32_t i = 0; i < x->u.map.len; i++) {
        const size_t entry_at = rec(e, N_MapEntry, 0, NOPOS, NOPOS, 0, -1, -1);
        KID(&k);
        int entry_kids = 0;
        enc_expr(e, x->u.map.ptr[i].key, &entry_kids);
        enc_expr(e, x->u.map.ptr[i].value, &entry_kids);
        patch(e, entry_at, entry_kids);
    }
    patch(e, at, k);
}

static void enc_call(Enc *e, const MsExpr *x, int *kids) {
    const size_t at = open_expr(e, x, N_Call, 0, -1, -1, kids);
    int k = 0;
    enc_expr(e, x->u.call.callee, &k);
    const size_t list_at = list_open(e, &k);
    int list_kids = 0;
    for (uint32_t i = 0; i < x->u.call.args.len; i++) {
        const MsArg *arg = &x->u.call.args.ptr[i];
        const size_t arg_at =
            rec(e, N_Arg, 0, arg->pos, NOPOS, arg->has_name ? 1 : 0, arg->has_name ? (int64_t)arg->name : -1, -1);
        KID(&list_kids);
        int arg_kids = 0;
        enc_expr(e, arg->value, &arg_kids);
        patch(e, arg_at, arg_kids);
    }
    patch(e, list_at, list_kids);
    patch(e, at, k);
}

static void enc_arm(Enc *e, const MsArm *arm, int *kids) {
    const size_t at = rec(e, N_Arm, arm->id, arm->pos, NOPOS, (arm->from_if ? 1 : 0) | (arm->bare ? 2 : 0), -1, -1);
    KID(kids);
    int k = 0;
    enc_expr(e, arm->path, &k);
    const size_t bindings_at = list_open(e, &k);
    int binding_kids = 0;
    for (uint32_t i = 0; i < arm->bindings.len; i++) {
        rec(e, N_ArmBinding, 0, arm->bindings.ptr[i].pos, NOPOS, 0, arm->bindings.ptr[i].name, -1);
        KID(&binding_kids);
    }
    patch(e, bindings_at, binding_kids);
    enc_body(e, arm->body.ptr, arm->body.len, &k);
    enc_expr(e, arm->value, &k);
    patch(e, at, k);
}

static void enc_match(Enc *e, const MsExpr *x, int *kids) {
    const size_t at = open_expr(e, x, N_Match, 0, -1, -1, kids);
    int k = 0;
    enc_expr(e, x->u.match.scrutinee, &k);
    const size_t arms_at = list_open(e, &k);
    int arm_kids = 0;
    for (uint32_t i = 0; i < x->u.match.arms.len; i++) enc_arm(e, x->u.match.arms.ptr[i], &arm_kids);
    patch(e, arms_at, arm_kids);
    patch(e, at, k);
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
    case MS_E_TEXT: enc_text(e, x, kids); break;
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
    case MS_E_MAP: enc_map(e, x, kids); break;
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
    case MS_E_CALL: enc_call(e, x, kids); break;
    default: enc_match(e, x, kids); break;
    }
#undef OPEN
}

static void enc_stmt(Enc *e, const MsStmt *s, int *kids) {
    size_t at;
    int k = 0;
#define OPEN(kind, flags, a, b) (at = rec(e, kind, s->id, s->pos, NOPOS, flags, a, b), KID(kids))
    switch (s->kind) {
    case MS_S_BIND:
        OPEN(N_Bind, (s->u.bind.is_mutable ? 1 : 0) | (s->u.bind.has_group ? 2 : 0), -1, -1);
        if (s->u.bind.has_group) {
            const size_t base = at * MS_TOOL_NODE_WIDTH;
            field_store(e->out, base + 5, s->u.bind.group.offset);
            field_store(e->out, base + 6, s->u.bind.group.line);
            field_store(e->out, base + 7, s->u.bind.group.column);
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
        OPEN(N_If, s->u.branch.is_mutable ? 1 : 0, -1, -1);
        enc_pattern(e, s->u.branch.binding, &k);
        enc_expr(e, s->u.branch.cond, &k);
        enc_body(e, s->u.branch.body.ptr, s->u.branch.body.len, &k);
        enc_body(e, s->u.branch.else_body.ptr, s->u.branch.else_body.len, &k);
        break;
    case MS_S_WHILE:
        OPEN(N_While, 0, -1, -1);
        enc_expr(e, s->u.loop.cond, &k);
        enc_body(e, s->u.loop.body.ptr, s->u.loop.body.len, &k);
        break;
    default:
        OPEN(N_For, 0, s->u.each.name, -1);
        enc_expr(e, s->u.each.iter, &k);
        enc_body(e, s->u.each.body.ptr, s->u.each.body.len, &k);
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
    int64_t base = (d->is_exported ? 1 : 0) | (d->synthetic ? 2 : 0);
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
        OPEN(N_Enum, d->u.enumeration.opaque ? 8 : 0, d->u.enumeration.name, -1);
        enc_type_params(e, d->u.enumeration.type_params, &k);
        size_t lat = list_open(e, &k);
        int lk = 0;
        for (uint32_t i = 0; i < d->u.enumeration.cases.len; i++) {
            const MsCase *c = d->u.enumeration.cases.ptr[i];
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
    const size_t count = t->nodes.len / sizeof(int64_t);
    for (size_t i = 0; i < count; i++) push_int(out, field_load(&t->nodes, i));
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

void ms_tool_keywords(ms_list *out) {
    for (int kind = MS_T_And; kind <= MS_T_While; kind++) {
        const char *word = ms_tok_str((MsTok)kind);
        ms_value value;
        memset(&value, 0, sizeof value);
        value.kind = MS_STRING;
        value.as.buf.data = (const uint8_t *)word;
        value.as.buf.len = strlen(word);
        ms_list_push(out, &value);
    }
}
