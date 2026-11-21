/* The tool interface (include/ms/tool.h): flat tables for Manuscript programs. */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/diag.h"
#include "ms/effects.h"
#include "ms/facts.h"
#include "ms/format.h"
#include "ms/lex.h"
#include "ms/ownership.h"
#include "ms/packages.h"
#include "ms/parse.h"
#include "ms/program.h"
#include "ms/project.h"
#include "ms/std_embed.h"
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

static uint8_t install_run(MsArena *arena, MsInstallOptions options, ms_list *out, ms_str *message_out) {
    MsInstallReport report = {0};
    MsProjectError error = {0};
    uint8_t status = 0;
    if (!ms_install(arena, &options, &report, &error)) {
        const char *text = ms_project_error_text(arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = 1;
    }
    for (uint32_t i = 0; status == 0 && i < report.count; i++) {
        const MsInstalledCopy *c = &report.copies[i];
        push_text(out, ms_arena_fmt(arena, "%s\t%s\t%s\t%s\t%s", c->name, c->copy.entry.spec, c->copy.entry.revision,
                                    install_state_name(c->state), c->effects).ptr);
    }
    return status;
}

static const char **install_names(MsArena *arena, const ms_list *update, size_t *count) {
    *count = ms_list_len(update);
    const char **names = MS_NEW_N(arena, const char *, *count + 1);
    for (size_t i = 0; i < *count; i++) {
        ms_value value = ms_list_get(update, i);
        names[i] = ms_arena_strndup(arena, (const char *)value.as.buf.data, value.as.buf.len);
        ms_value_free(&value);
    }
    return names;
}

uint8_t ms_tool_install(const ms_str *manifest, const ms_list *update, uint8_t locked, uint8_t frozen, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    size_t count = 0;
    const char **names = install_names(&arena, update, &count);
    const MsInstallOptions options = {.manifest = ms_arena_strndup(&arena, (const char *)ms_str_data(manifest), ms_str_len(manifest)),
                                      .update = names, .update_count = (uint32_t)count, .locked = locked != 0, .frozen = frozen != 0};
    const uint8_t status = install_run(&arena, options, out, message_out);
    ms_arena_free(&arena);
    return status;
}

uint8_t ms_tool_workspace(const ms_str *manifest, uint8_t root_only, ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    const char *path = ms_arena_strndup(&arena, (const char *)ms_str_data(manifest), ms_str_len(manifest));
    MsWorkspace workspace = {0};
    MsProjectError error = {0};
    bool found = false;
    const bool ok = root_only != 0 ? ms_workspace_root_members(&arena, path, &workspace, &found, &error) : ms_workspace_find(&arena, path, &workspace, &found, &error);
    uint8_t status = 0;
    if (!ok) {
        const char *text = ms_project_error_text(&arena, &error);
        ms_string_new((const uint8_t *)text, strlen(text), message_out);
        status = ms_project_error_is_unsupported(&error) ? 2 : 1;
    } else if (found) {
        push_row(&arena, out, "root", workspace.root, NULL);
        for (uint32_t i = 0; i < workspace.count; i++) {
            push_row(&arena, out, "member", workspace.members[i].name, workspace.members[i].root);
        }
    }
    ms_arena_free(&arena);
    return status;
}

uint8_t ms_tool_requirement(const ms_str *text, ms_list *out, ms_str *message_out) {
    (void)out;
    MsArena arena = {0};
    const char *source = ms_arena_strndup(&arena, (const char *)ms_str_data(text), ms_str_len(text));
    MsRequirement requirement;
    const char *error = "";
    const bool ok = ms_requirement_parse(&arena, source, &requirement, &error);
    if (!ok) {
        ms_string_new((const uint8_t *)error, strlen(error), message_out);
    }
    ms_arena_free(&arena);
    return ok ? 0 : 1;
}

uint8_t ms_tool_install_workspace(const ms_str *lock_root, const ms_list *members, const ms_list *update, uint8_t locked, uint8_t frozen,
                                  ms_list *out, ms_str *message_out) {
    MsArena arena = {0};
    size_t count = 0;
    const char **names = install_names(&arena, update, &count);
    /* Members are `name\tmanifest` rows. */
    const size_t total = ms_list_len(members);
    const char **member_names = MS_NEW_N(&arena, const char *, total + 1);
    const char **manifests = MS_NEW_N(&arena, const char *, total + 1);
    for (size_t i = 0; i < total; i++) {
        ms_value value = ms_list_get(members, i);
        const char *row = ms_arena_strndup(&arena, (const char *)value.as.buf.data, value.as.buf.len);
        ms_value_free(&value);
        const char *tab = strchr(row, '\t');
        member_names[i] = tab == NULL ? row : ms_arena_strndup(&arena, row, (size_t)(tab - row));
        manifests[i] = tab == NULL ? row : tab + 1;
    }
    const MsInstallOptions options = {.lock_root = ms_arena_strndup(&arena, (const char *)ms_str_data(lock_root), ms_str_len(lock_root)),
                                      .member_names = member_names, .member_manifests = manifests, .member_count = (uint32_t)total,
                                      .update = names, .update_count = (uint32_t)count, .locked = locked != 0, .frozen = frozen != 0};
    const uint8_t status = install_run(&arena, options, out, message_out);
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

/* ---- analysis for the language server ---- */

static void push_name(ms_list *out, const char *data, size_t len) {
    ms_value value;
    memset(&value, 0, sizeof value);
    value.kind = MS_STRING;
    value.as.buf.data = (const uint8_t *)data;
    value.as.buf.len = len;
    ms_list_push(out, &value);
}

/* The result of ms_tool_analyze: the rows and name texts, kept in C until the caller reads them. */
typedef struct Analysis {
    uint8_t status; /* 0 analysed, 1 syntax error, 2 not covered */
    char *message;
    int64_t *rows;
    size_t nrows, rows_cap;
    int64_t *effects; /* the effect rows, taken before the ownership pass, which leaves unfollowed functions unchecked */
    size_t neffects, effects_cap;
    char **names;
    size_t *name_lens;
    size_t nnames, names_cap;
} Analysis;

static void analysis_drop(void *payload) {
    Analysis *a = payload;
    free(a->message);
    free(a->rows);
    free(a->effects);
    for (size_t i = 0; i < a->nnames; i++) {
        free(a->names[i]);
    }
    free(a->names);
    free(a->name_lens);
}

static void put_row(Analysis *a, int64_t v) {
    if (a->nrows == a->rows_cap) {
        a->rows_cap = a->rows_cap == 0 ? 256 : a->rows_cap * 2;
        a->rows = ms_array_resize(a->rows, (uint32_t)a->rows_cap, sizeof *a->rows);
    }
    a->rows[a->nrows++] = v;
}

static void put_effect_row(Analysis *a, int64_t v) {
    if (a->neffects == a->effects_cap) {
        a->effects_cap = a->effects_cap == 0 ? 32 : a->effects_cap * 2;
        a->effects = realloc(a->effects, a->effects_cap * sizeof *a->effects);
    }
    a->effects[a->neffects++] = v;
}

static int64_t put_name(Analysis *a, const char *data, size_t len) {
    if (a->nnames == a->names_cap) {
        a->names_cap = a->names_cap == 0 ? 64 : a->names_cap * 2;
        a->names = ms_array_resize(a->names, (uint32_t)a->names_cap, sizeof *a->names);
        a->name_lens = ms_array_resize(a->name_lens, (uint32_t)a->names_cap, sizeof *a->name_lens);
    }
    char *copy = malloc(len + 1);
    memcpy(copy, data, len);
    copy[len] = 0;
    a->names[a->nnames] = copy;
    a->name_lens[a->nnames] = len;
    return (int64_t)a->nnames++;
}

/* The type as source reads it; -1 for no type. */
static int64_t put_type(Analysis *a, const MsCheck *c, MsTy ty) {
    if (ty == MS_TY_NONE) {
        return -1;
    }
    MsBuf text = {0};
    ms_ty_show(&text, c->names, &c->tys, ty);
    const int64_t at = put_name(a, text.data == NULL ? "" : (const char *)text.data, text.len);
    ms_buf_free(&text);
    return at;
}

/* Whether node `n` has a resolution or a type to report. */
static bool analyzed(const MsFacts *facts, uint32_t n) {
    return facts->res_kind[n] != MS_RES_NONE || facts->call_callee[n] != MS_NONE || facts->expr_ty[n] != MS_TY_NONE || facts->type_ref_ty[n] != MS_TY_NONE;
}

static void fail(Analysis *a, uint8_t status, const char *text, size_t len) {
    a->status = status;
    a->message = malloc(len + 1);
    memcpy(a->message, text, len);
    a->message[len] = 0;
}

/* Whether the receiver of a method row is the type `ty`, or the same nominal type with other arguments (the row
 * of `WriteStream[T].flush` serves a `WriteStream[String]`). */
static bool analyze_same_receiver(const MsTyTable *tys, MsTy receiver, MsTy ty) {
    return receiver == ty || (tys->def[ty] != 0 && tys->def[receiver] == tys->def[ty] && tys->kind[receiver] == tys->kind[ty]);
}

/* The first method of `ty` that takes nothing, returns a `Result` and is named `flush` or `commit`: what
 * a scope that closes a resource does not run. The name's index, -1 for none. */
static int64_t analyze_finisher(Analysis *a, const MsCheck *check, const MsFacts *facts, MsTy ty) {
    const MsMethods *methods = facts->methods;
    for (uint32_t i = 0; methods != NULL && i < methods->count; i++) {
        if (!analyze_same_receiver(&check->tys, methods->receiver[i], ty) || methods->decl[i] == NULL || methods->ty[i] == MS_TY_NONE) {
            continue;
        }
        const MsTy signature = methods->ty[i];
        const MsStr name = ms_name(check->names, methods->decl[i]->name);
        const bool finishes = (name.len == 5 && memcmp(name.ptr, "flush", 5) == 0) ||
                              (name.len == 6 && memcmp(name.ptr, "commit", 6) == 0);
        if (finishes && check->tys.nparams[signature] == 0 && ms_ty_is(&check->tys, check->tys.result[signature], MS_BI_RESULT)) {
            return put_name(a, name.ptr, name.len);
        }
    }
    return -1;
}

/* The ownership rows, after the symbols: the count and ids of the name nodes that move a value out, then the count
 * of resource bindings and for each its index, 1 when the ownership pass followed its function, and the name of its
 * finisher (-1 for none). */
static void analyze_ownership(Analysis *a, const MsCheck *check, const MsFacts *facts) {
    int64_t moves = 0, resources = 0;
    for (uint32_t n = 0; n <= facts->node_count; n++) {
        moves += facts->moved_out[n];
    }
    for (uint32_t k = 0; k < facts->bindings.count; k++) {
        resources += (facts->bindings.flags[k] & MS_BIND_RESOURCE) != 0;
    }
    put_row(a, moves);
    for (uint32_t n = 0; n <= facts->node_count; n++) {
        if (facts->moved_out[n]) {
            put_row(a, n);
        }
    }
    put_row(a, resources);
    for (uint32_t k = 0; k < facts->bindings.count; k++) {
        if ((facts->bindings.flags[k] & MS_BIND_RESOURCE) == 0) {
            continue;
        }
        const uint32_t callable = facts->bindings.callable[k];
        put_row(a, k);
        put_row(a, callable <= facts->node_count && facts->body_checked[callable] ? 1 : 0);
        put_row(a, analyze_finisher(a, check, facts, facts->bindings.ty[k]));
    }
}

/* Takes the effect rows of module `id`: 1 when the scan saw every callable it reached (a missing violation proves
 * nothing otherwise), the count of violations of the module's own callables, and for each its offset, line, column and
 * the message `ms lint` prints as MSL116. Run before the ownership pass, which leaves a function it cannot follow
 * unchecked, and so invisible to the scan. */
static void collect_effects(Analysis *a, const MsCheck *check, MsModId id) {
    MsArena arena = {0};
    const MsEffectModule module = {.id = id, .text = check->mods[id].text};
    MsPackageViolation *violations = NULL;
    uint32_t count = 0;
    bool complete = false;
    if (!ms_effect_project_violations(&arena, check, &module, 1, &violations, &count, &complete)) {
        count = 0;
        complete = false;
    }
    a->neffects = 0;
    put_effect_row(a, complete ? 1 : 0);
    put_effect_row(a, count);
    for (uint32_t k = 0; k < count; k++) {
        put_effect_row(a, violations[k].pos.offset);
        put_effect_row(a, violations[k].pos.line);
        put_effect_row(a, violations[k].pos.column);
        put_effect_row(a, put_name(a, violations[k].message, strlen(violations[k].message)));
    }
    ms_arena_free(&arena);
}

static void analyze_facts(Analysis *a, const MsCheck *check, MsModId id) {
    const MsFacts *facts = check->mods[id].facts;
    const MsNames *table = check->names;
    if (facts == NULL) {
        return;
    }
    /* Header: node rows, binding rows, symbol rows. */
    int64_t nodes = 0, symbols = 0;
    bool *seen = calloc(check->syms.count + 1, sizeof *seen);
    for (uint32_t n = 0; n <= facts->node_count; n++) {
        nodes += analyzed(facts, n);
        if (seen != NULL && facts->res_kind[n] == MS_RES_SYMBOL && facts->res_ref[n] < check->syms.count) {
            seen[facts->res_ref[n]] = true;
        }
        if (seen != NULL && facts->call_callee[n] != MS_NONE && facts->call_callee[n] < check->syms.count) {
            seen[facts->call_callee[n]] = true;
        }
    }
    for (uint32_t s = 0; seen != NULL && s < check->syms.count; s++) {
        symbols += seen[s];
    }
    put_row(a, nodes);
    put_row(a, facts->bindings.count);
    put_row(a, symbols);
    for (uint32_t n = 0; n <= facts->node_count; n++) {
        if (!analyzed(facts, n)) {
            continue;
        }
        put_row(a, n);
        put_row(a, facts->res_kind[n]);
        put_row(a, facts->res_kind[n] == MS_RES_NONE ? -1 : (int64_t)facts->res_ref[n]);
        put_row(a, put_type(a, check, facts->expr_ty[n]));
        put_row(a, put_type(a, check, facts->type_ref_ty[n]));
        put_row(a, facts->call_callee[n] == MS_NONE ? -1 : (int64_t)facts->call_callee[n]);
    }
    const MsBindings *b = &facts->bindings;
    for (uint32_t k = 0; k < b->count; k++) {
        const MsStr name = ms_name(table, b->name[k]);
        put_row(a, put_name(a, name.ptr, name.len));
        put_row(a, put_type(a, check, b->ty[k]));
        put_row(a, b->decl_node[k]);
        put_row(a, b->pos[k].line);
        put_row(a, b->pos[k].column);
        put_row(a, b->pos[k].offset);
        put_row(a, b->role[k]);
        put_row(a, b->flags[k]);
        put_row(a, b->reads[k]);
    }
    /* Every symbol a name resolved to, once, in id order. */
    for (uint32_t s = 0; seen != NULL && s < check->syms.count; s++) {
        if (!seen[s]) {
            continue;
        }
        const MsStr name = ms_name(table, check->syms.name[s]);
        const MsModId home = check->syms.module[s];
        const MsStr path = home == MS_NONE ? (MsStr){"", 0} : ms_name(table, check->mods[home].path);
        const MsDecl *decl = check->syms.decl[s];
        put_row(a, s);
        put_row(a, put_name(a, name.ptr, name.len));
        put_row(a, check->syms.kind[s]);
        put_row(a, put_name(a, path.ptr, path.len));
        put_row(a, home == id ? 1 : 0);
        put_row(a, check->syms.is_exported[s] ? 1 : 0);
        put_row(a, decl == NULL ? -1 : (int64_t)decl->id);
        put_row(a, decl == NULL ? 0 : decl->pos.offset);
        put_row(a, decl == NULL ? 0 : decl->pos.line);
        put_row(a, decl == NULL ? 0 : decl->pos.column);
        put_row(a, put_type(a, check, check->syms.ty[s]));
    }
    free(seen);
    analyze_ownership(a, check, facts);
    for (size_t i = 0; i < a->neffects; i++) {
        put_row(a, a->effects[i]);
    }
}

/* Loads the project `path` belongs to, with `overlay` (path, text pairs) in place of disk, and checks every module of
 * its graph; the facts of the entry (the last module) are the result. Status 2 when the graph does not load. */
static void analyze_project(Analysis *a, MsCheck *check, MsNames *table, const char *path, const MsOverlay *overlay) {
    MsArena graph_arena = {0};
    MsGraph graph;
    MsProjectError error = {0};
    if (!ms_project_load_overlay(&graph_arena, table, path, overlay, &graph, &error) || graph.ndiagnostics != 0 ||
        graph.count == 0) {
        fail(a, 2, "the project does not load", 25);
    } else {
        MsModId *ids = MS_NEW_N(&graph_arena, MsModId, graph.count);
        ms_graph_add_modules(check, table, &graph_arena, &graph, ids);
        ms_program_begin(check);
        (void)ms_graph_check(check, &graph, ids, NULL);
        collect_effects(a, check, ids[graph.count - 1]);
        for (uint32_t i = 0; i < graph.count; i++) {
            ms_module_check_ownership(check, ids[i]);
        }
        analyze_facts(a, check, ids[graph.count - 1]);
    }
    ms_arena_free(&graph_arena);
}

ms_object *ms_tool_analyze(const ms_str *path, const ms_str *text, const ms_list *overlay) {
    ms_object *obj = ms_object_new(sizeof(Analysis), analysis_drop);
    Analysis *a = ms_payload(obj);
    const char *src = (const char *)ms_str_data(text);
    const size_t len = ms_str_len(text);
    if (!ms_utf8_valid(src, len)) {
        fail(a, 1, "invalid UTF-8", 13);
        return obj;
    }
    MsNames table;
    ms_names_init(&table);
    MsArena syntax = {0};
    MsModule module;
    MsDiag diag;
    /* Not ms_str_cstring: this archive's free() is mimalloc's, the runtime's is not. */
    const size_t entry_len = ms_str_len(path);
    char *entry = malloc(entry_len + 1);
    memcpy(entry, ms_str_data(path), entry_len);
    entry[entry_len] = 0;
    const bool named = entry_len != 0 && strlen(entry) == entry_len;
    if (!ms_parse(&syntax, &table, src, len, &module, &diag)) {
        fail(a, 1, diag.message.ptr, diag.message.len);
    } else if (!named && !ms_module_only_std_imports(&module)) {
        fail(a, 2, "imports a project module", 24);
    } else {
        MsCheck check;
        ms_check_init(&check, &table);
        uint32_t nfiles = 0;
        const MsStdFile *files = ms_std_embedded(&nfiles);
        MsStr err = {0};
        if (!ms_std_load(&check, &syntax, files, nfiles, &err)) {
            fail(a, 1, err.ptr, err.len);
        } else if (named) {
            /* The entry's text and every other open buffer replace the files on disk. */
            const size_t pairs = ms_list_len(overlay) / 2;
            MsOverlayFile *rows = calloc(pairs + 1, sizeof *rows);
            ms_value *held = calloc(2 * pairs + 1, sizeof *held);
            char **file_paths = calloc(pairs + 1, sizeof *file_paths);
            uint32_t count = 0;
            for (size_t i = 0; i < pairs; i++) {
                held[2 * i] = ms_list_get(overlay, 2 * i);
                held[2 * i + 1] = ms_list_get(overlay, 2 * i + 1);
                const size_t file_len = held[2 * i].as.buf.len;
                file_paths[i] = malloc(file_len + 1);
                memcpy(file_paths[i], held[2 * i].as.buf.data, file_len);
                file_paths[i][file_len] = 0;
                if (strlen(file_paths[i]) == file_len) {
                    rows[count++] = (MsOverlayFile){file_paths[i], (const char *)held[2 * i + 1].as.buf.data,
                                                    held[2 * i + 1].as.buf.len};
                }
            }
            rows[count++] = (MsOverlayFile){entry, src, len};
            const MsOverlay all = {rows, count};
            analyze_project(a, &check, &table, entry, &all);
            for (size_t i = 0; i < pairs; i++) {
                ms_value_free(&held[2 * i]);
                ms_value_free(&held[2 * i + 1]);
                free(file_paths[i]);
            }
            free(file_paths);
            free(held);
            free(rows);
        } else {
            const MsModId id = ms_module_add(&check, ms_intern_cstr(&table, "main.ms"), &module);
            ms_program_begin(&check);
            (void)ms_program_check_module(&check, id, (MsStr){src, (uint32_t)len});
            collect_effects(a, &check, id);
            ms_module_check_ownership(&check, id);
            analyze_facts(a, &check, id);
        }
        ms_check_free(&check);
    }
    free(entry);
    ms_arena_free(&syntax);
    ms_names_free(&table);
    return obj;
}

uint8_t ms_tool_analysis_status(ms_object *analysis) { return ((Analysis *)ms_payload(analysis))->status; }

void ms_tool_analysis_message(ms_object *analysis, ms_str *out) {
    const Analysis *a = ms_payload(analysis);
    if (a->message != NULL) {
        ms_string_new((const uint8_t *)a->message, strlen(a->message), out);
    }
}

void ms_tool_analysis_rows(ms_object *analysis, ms_list *out) {
    const Analysis *a = ms_payload(analysis);
    for (size_t i = 0; i < a->nrows; i++) {
        push_int(out, a->rows[i]);
    }
}

void ms_tool_analysis_names(ms_object *analysis, ms_list *out) {
    const Analysis *a = ms_payload(analysis);
    for (size_t i = 0; i < a->nnames; i++) {
        push_name(out, a->names[i], a->name_lens[i]);
    }
}
