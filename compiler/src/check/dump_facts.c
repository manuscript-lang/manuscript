/* The fact model of one module as JSON: the document `tools/ms/views.ms` reads and
 * `ms-tooling-dev facts` prints from the Rust checker (crates/ms-tooling/src/collect.rs).
 * Stage 1 prints what the syntax tree gives: entity key, kind, name, line, slots, result, receiver
 * mode and try count. The fields that need checker columns (calls, effects, error type, passing
 * modes, referenced types, resource scopes, flows) are printed empty and are compared only once
 * their column exists (compiler/tests/facts-diff.sh). */
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"
#include "ms/effects.h"
#include "ms/facts.h"
#include "ms/walk.h"

typedef struct FactsRow {
    const char *kind;
    MsBuf name;
    MsBuf key;
    uint32_t line;
    MsBuf body; /* the JSON fields after `line`: slots, result, receiver, tries */
    MsBuf effects; /* the JSON fields effects, reach, permits and calls */
    MsBuf meta;    /* the JSON fields ty, error and exported */
    uint32_t first, last; /* the lines the entity owns: its own line to the line before the next entity */
    uint32_t scopes;      /* the bindings that close at scope end */
    bool own_known;       /* the ownership columns (modes, result ownership, scopes) are the checker's */
} FactsRow;

static void facts_put_str(MsBuf *out, const MsNames *names, MsSym s) {
    const MsStr text = ms_name(names, s);
    ms_buf_put(out, text.ptr, text.len);
}

/* The type as written, with its arguments (`type_text` in collect.rs). */
static void facts_put_type_text(MsBuf *out, const MsNames *names, const MsTypeRef *t) {
    if (t == NULL) {
        return;
    }
    if (t->kind == MS_TYPE_NAMED) {
        facts_put_str(out, names, t->name);
        for (uint32_t i = 0; i < t->args.len; i++) {
            ms_buf_puts(out, i == 0 ? "[" : ", ");
            facts_put_type_text(out, names, t->args.ptr[i]);
        }
        if (t->args.len > 0) {
            ms_buf_putc(out, ']');
        }
        return;
    }
    ms_buf_puts(out, "fn(");
    bool first = true;
    for (uint32_t i = 0; i < t->params.len; i++) {
        if (t->params.ptr[i]->ty == NULL) {
            continue;
        }
        ms_buf_puts(out, first ? "" : ", ");
        first = false;
        facts_put_type_text(out, names, t->params.ptr[i]->ty);
    }
    ms_buf_puts(out, ") ");
    facts_put_type_text(out, names, t->result);
}

/* A JSON string of `text`, escaped as the Rust writer's html-safe form does. */
static void facts_put_json(MsBuf *out, const char *text, size_t len) {
    ms_buf_putc(out, '"');
    for (size_t i = 0; i < len; i++) {
        const unsigned char ch = (unsigned char)text[i];
        if (ch == '"' || ch == '\\') {
            ms_buf_putc(out, '\\');
            ms_buf_putc(out, (char)ch);
        } else if (ch == '\n') {
            ms_buf_puts(out, "\\n");
        } else if (ch == '\r') {
            ms_buf_puts(out, "\\r");
        } else if (ch == '\t') {
            ms_buf_puts(out, "\\t");
        } else if (ch < 0x20 || ch == '<' || ch == '>' || ch == '&') {
            ms_buf_printf(out, "\\u%04x", ch);
        } else {
            ms_buf_putc(out, (char)ch);
        }
    }
    ms_buf_putc(out, '"');
}

static void facts_put_json_buf(MsBuf *out, const MsBuf *text) { facts_put_json(out, text->data == NULL ? "" : text->data, text->len); }

static void facts_put_slot(MsBuf *out, const MsNames *names, MsSym name, const MsTypeRef *ty, bool exclusive, const char *mode) {
    MsBuf text = {0};
    MsBuf label = {0};
    facts_put_str(&label, names, name);
    facts_put_type_text(&text, names, ty);
    ms_buf_puts(out, "{\"name\": ");
    facts_put_json_buf(out, &label);
    ms_buf_puts(out, ", \"ty\": ");
    facts_put_json_buf(out, &text);
    ms_buf_printf(out, ", \"exclusive\": %s, \"mode\": \"%s\", \"refs\": []}", exclusive ? "true" : "false", mode);
    ms_buf_free(&text);
    ms_buf_free(&label);
}

/* The slots of `params`; `modes`, when set, holds each one's passing mode, else they print "". */
static void facts_put_params(MsBuf *out, const MsNames *names, MsParams params, const char *const *modes) {
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < params.len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ", ");
        facts_put_slot(out, names, params.ptr[i]->name, params.ptr[i]->ty, params.ptr[i]->is_mutable,
                       modes == NULL ? "" : modes[i]);
    }
    ms_buf_putc(out, ']');
}

/* `(name: Type, ..)` as the Rust slot text of a case payload or operation. */
static void facts_put_param_text(MsBuf *out, const MsNames *names, MsParams params) {
    for (uint32_t i = 0; i < params.len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ", ");
        facts_put_str(out, names, params.ptr[i]->name);
        ms_buf_puts(out, ": ");
        facts_put_type_text(out, names, params.ptr[i]->ty);
    }
}

typedef struct FactsTryCount {
    uint32_t tries;
} FactsTryCount;

static void facts_count_try(void *ctx, const MsExpr *e) {
    if (e->kind == MS_E_UNARY && e->op == MS_U_TRY) {
        ((FactsTryCount *)ctx)->tries++;
    }
}

static uint32_t facts_tries_of(MsParams params, MsStmts body) {
    FactsTryCount count = {0};
    const MsVisitor visitor = {.ctx = &count, .expr = facts_count_try};
    ms_walk_callable(&visitor, params, body);
    return count.tries;
}

/* Appends `, "result": ..., "receiver": ..., "tries": N` and the fields no column feeds yet. */
/* The tail of an entity: ownership and receiver, tries, and the result slot with type `text` (none when NULL). */
static void facts_put_tail_text(MsBuf *out, const char *receiver, uint32_t tries, MsBuf *text, const char *ownership) {
    ms_buf_printf(out, ", \"result_ownership\": \"%s\", \"result_borrow\": %s, \"receiver\": \"", ownership,
                  strcmp(ownership, "borrow") == 0 ? "true" : "false");
    ms_buf_puts(out, receiver);
    ms_buf_printf(out, "\", \"tries\": %u", tries);
    ms_buf_puts(out, ", \"result\": ");
    if (text == NULL) {
        ms_buf_puts(out, "null");
        return;
    }
    ms_buf_puts(out, "{\"name\": \"\", \"ty\": ");
    facts_put_json_buf(out, text);
    ms_buf_puts(out, ", \"exclusive\": false, \"mode\": \"\", \"refs\": []}");
}

static void facts_put_tail(MsBuf *out, const MsNames *names, const MsTypeRef *result, const char *receiver, uint32_t tries,
                           const char *ownership) {
    if (result == NULL) {
        facts_put_tail_text(out, receiver, tries, NULL, ownership);
        return;
    }
    MsBuf text = {0};
    facts_put_type_text(&text, names, result);
    facts_put_tail_text(out, receiver, tries, &text, ownership);
    ms_buf_free(&text);
}

static FactsRow *facts_add_row(MsBuf *rows, const MsNames *names, const char *file, const char *kind, uint32_t line) {
    (void)names;
    FactsRow *row = ms_buf_push(rows, sizeof *row);
    memset(row, 0, sizeof *row);
    row->kind = kind;
    row->line = line;
    ms_buf_printf(&row->key, "%s#%s#", file, kind);
    return row;
}

static void facts_seal_key(FactsRow *row) { ms_buf_put(&row->key, row->name.data, row->name.len); }

static int facts_compare_rows(const void *a, const void *b) {
    const FactsRow *x = a, *y = b;
    const size_t n = x->key.len < y->key.len ? x->key.len : y->key.len;
    const int order = memcmp(x->key.data, y->key.data, n);
    if (order != 0) {
        return order;
    }
    if (x->key.len != y->key.len) {
        return x->key.len < y->key.len ? -1 : 1;
    }
    return x->line < y->line ? -1 : x->line > y->line; /* equal keys: the earlier declaration first */
}

static const char *facts_kind_of(const MsDecl *d) {
    switch (d->kind) {
    case MS_D_FN: return "fn";
    case MS_D_CONST: return "constant";
    case MS_D_TYPE: return "type";
    case MS_D_ENUM: return "alternative";
    case MS_D_ALIAS: return "alias";
    case MS_D_INTERFACE: return "interface";
    case MS_D_IMPL: return "impl";
    default: return d->u.test.bench ? "bench" : "test";
    }
}

/* The impl's display name: `Contract for Type`, or `Type` for an inherent or synthesized impl. */
static void facts_put_impl_name(MsBuf *out, const MsNames *names, const MsDecl *d) {
    if (d->u.impl.contract != NULL && !d->synthetic) {
        facts_put_str(out, names, d->u.impl.contract->kind == MS_TYPE_NAMED ? d->u.impl.contract->name : 0);
        ms_buf_puts(out, " for ");
    }
    facts_put_str(out, names, d->u.impl.receiver->kind == MS_TYPE_NAMED ? d->u.impl.receiver->name : 0);
}

/* What groups inherent impls into one block (as the desugaring does): the receiver as written and
 * the written bounds. */
static void facts_put_group_type(MsBuf *out, const MsNames *names, const MsTypeRef *t) {
    if (t->kind == MS_TYPE_NAMED) {
        facts_put_str(out, names, t->name);
        ms_buf_putc(out, '[');
        for (uint32_t i = 0; i < t->args.len; i++) {
            ms_buf_puts(out, i == 0 ? "" : ",");
            facts_put_group_type(out, names, t->args.ptr[i]);
        }
        ms_buf_putc(out, ']');
        return;
    }
    ms_buf_puts(out, "fn(");
    for (uint32_t i = 0; i < t->params.len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ",");
        ms_buf_puts(out, t->params.ptr[i]->is_mutable ? "var " : "");
        if (t->params.ptr[i]->ty != NULL) {
            facts_put_group_type(out, names, t->params.ptr[i]->ty);
        }
    }
    ms_buf_putc(out, ')');
    facts_put_group_type(out, names, t->result);
}

static void facts_group_key(MsBuf *out, const MsNames *names, const MsDecl *impl) {
    facts_put_group_type(out, names, impl->u.impl.receiver);
    for (uint32_t i = 0; i < impl->u.impl.bounds.len; i++) {
        const MsTypeParam *bound = impl->u.impl.bounds.ptr[i];
        ms_buf_putc(out, ';');
        facts_put_str(out, names, bound->name);
        for (uint32_t k = 0; k < bound->bounds.len; k++) {
            ms_buf_putc(out, '&');
            facts_put_type_text(out, names, bound->bounds.ptr[k]);
        }
    }
}

/* The line of the first inherent impl with the same receiver and bounds as `module->decls[at]`: the
 * line the Rust inspection gives the grouped impl. */
static uint32_t facts_impl_line(const MsModule *module, const MsNames *names, uint32_t at) {
    const MsDecl *impl = module->decls[at];
    if (impl->u.impl.contract != NULL) {
        return impl->pos.line;
    }
    MsBuf key = {0};
    facts_group_key(&key, names, impl);
    uint32_t line = impl->pos.line;
    for (uint32_t i = 0; i < at; i++) {
        const MsDecl *other = module->decls[i];
        if (other->kind != MS_D_IMPL || other->u.impl.contract != NULL) {
            continue;
        }
        MsBuf other_key = {0};
        facts_group_key(&other_key, names, other);
        const bool same = other_key.len == key.len && memcmp(other_key.data, key.data, key.len) == 0;
        ms_buf_free(&other_key);
        if (same) {
            line = other->pos.line;
            break;
        }
    }
    ms_buf_free(&key);
    return line;
}

static void facts_put_case_slots(MsBuf *body, const MsNames *names, const MsDecl *d) {
    for (uint32_t i = 0; i < d->u.enumeration.cases.len; i++) {
        const MsCase *c = d->u.enumeration.cases.ptr[i];
        MsBuf name = {0}, text = {0};
        facts_put_str(&name, names, c->name);
        if (c->fields.len > 0) {
            ms_buf_putc(&text, '(');
            facts_put_param_text(&text, names, c->fields);
            ms_buf_putc(&text, ')');
        }
        ms_buf_puts(body, i == 0 ? "{\"name\": " : ", {\"name\": ");
        facts_put_json_buf(body, &name);
        ms_buf_puts(body, ", \"ty\": ");
        facts_put_json_buf(body, &text);
        ms_buf_puts(body, ", \"exclusive\": false, \"mode\": \"\", \"refs\": []}");
        ms_buf_free(&name);
        ms_buf_free(&text);
    }
}

static void facts_put_method_slots(MsBuf *body, const MsNames *names, const MsDecl *d) {
    for (uint32_t i = 0; i < d->u.iface.methods.len; i++) {
        const MsMethod *m = d->u.iface.methods.ptr[i];
        MsBuf name = {0}, text = {0};
        facts_put_str(&name, names, m->func.name);
        ms_buf_putc(&text, '(');
        facts_put_param_text(&text, names, m->func.params);
        ms_buf_puts(&text, ") ");
        facts_put_type_text(&text, names, m->func.result);
        ms_buf_puts(body, i == 0 ? "{\"name\": " : ", {\"name\": ");
        facts_put_json_buf(body, &name);
        ms_buf_puts(body, ", \"ty\": ");
        facts_put_json_buf(body, &text);
        ms_buf_printf(body, ", \"exclusive\": %s, \"mode\": \"\", \"refs\": []}", m->mutating ? "true" : "false");
        ms_buf_free(&name);
        ms_buf_free(&text);
    }
}

/* The slots of `params` without the brackets of facts_put_params. */
static void facts_put_inner_params(MsBuf *body, const MsNames *names, MsParams params, const char *const *modes) {
    MsBuf slots = {0};
    facts_put_params(&slots, names, params, modes);
    ms_buf_put(body, slots.data + 1, slots.len - 2);
    ms_buf_free(&slots);
}

typedef struct FactsOwn {
    MsCheck *check;
    MsModId module;
    MsClassifier *classifier;
} FactsOwn;

/* The passing mode of each parameter of a function the ownership walk kept, as the Rust collector
 * names it; false when the walk did not keep it, and `modes` is then unset. */
static bool facts_fn_modes(const FactsOwn *own, const MsDecl *d, const char **modes) {
    const MsFacts *facts = own->check->mods[own->module].facts;
    if (facts == NULL || facts->body_checked == NULL || !facts->body_checked[d->id]) {
        return false;
    }
    for (uint32_t i = 0; i < d->u.fn.params.len; i++) {
        const MsParam *param = d->u.fn.params.ptr[i];
        const MsTy ty = param->ty == NULL ? MS_TY_NONE : facts->type_ref_ty[param->ty->id];
        const bool consumed = i < 32 && ((facts->param_consumed[d->id] >> i) & 1u) != 0;
        modes[i] = "borrow";
        if (param->is_mutable) {
            modes[i] = "var";
        } else if (ty != MS_TY_NONE && ms_classify(own->classifier, ty) == MS_CLASS_COPY) {
            modes[i] = "copy";
        } else if (param->moving || consumed) {
            modes[i] = "move";
        }
    }
    return true;
}

/* The bindings of function `d` that close at scope end. */
static uint32_t facts_fn_scopes(const MsFacts *facts, const MsDecl *d) {
    uint32_t scopes = 0;
    for (uint32_t k = 0; k < facts->bindings.count; k++) {
        const bool closes = (facts->bindings.flags[k] & MS_BIND_RESOURCE) != 0;
        scopes += closes && facts->bindings.callable[k] == d->id ? 1u : 0u;
    }
    return scopes;
}

/* The slots and tail of a function: the ownership columns come from the walk when it kept the function. */
static void facts_fill_fn(FactsRow *row, const MsNames *names, const FactsOwn *own, const MsDecl *d) {
    const MsParams params = d->u.fn.params;
    const char **modes = calloc(params.len + 1, sizeof *modes);
    const MsFacts *facts = own->check->mods[own->module].facts;
    const bool known = modes != NULL && facts_fn_modes(own, d, modes);
    facts_put_str(&row->name, names, d->u.fn.name);
    ms_buf_puts(&row->body, ", \"slots\": [");
    facts_put_inner_params(&row->body, names, params, known ? modes : NULL);
    ms_buf_putc(&row->body, ']');
    row->own_known = known;
    row->scopes = known ? facts_fn_scopes(facts, d) : 0;
    const char *ownership = "";
    if (known) {
        ownership = facts->ret_borrowed[d->id] ? "borrow" : "owned";
    }
    facts_put_tail(&row->body, names, d->u.fn.result, "", facts_tries_of(params, d->u.fn.body), ownership);
    free(modes);
}

static void facts_fill_decl(FactsRow *row, const MsNames *names, const FactsOwn *own, const MsDecl *d) {
    if (d->kind == MS_D_FN) {
        facts_fill_fn(row, names, own, d);
        return;
    }
    MsBuf *body = &row->body;
    ms_buf_puts(body, ", \"slots\": [");
    const MsTypeRef *result = NULL;
    uint32_t tries = 0;
    switch (d->kind) {
    case MS_D_TYPE:
        facts_put_str(&row->name, names, d->u.type.name);
        facts_put_inner_params(body, names, d->u.type.fields, NULL);
        break;
    case MS_D_ENUM:
        facts_put_str(&row->name, names, d->u.enumeration.name);
        facts_put_case_slots(body, names, d);
        ms_buf_putc(body, ']');
        facts_put_tail(body, names, NULL, "", 0, "");
        return;
    case MS_D_INTERFACE:
        facts_put_str(&row->name, names, d->u.iface.name);
        facts_put_method_slots(body, names, d);
        ms_buf_putc(body, ']');
        facts_put_tail(body, names, NULL, "", 0, "");
        return;
    case MS_D_CONST:
        facts_put_str(&row->name, names, d->u.konst.name);
        break;
    case MS_D_ALIAS: {
        facts_put_str(&row->name, names, d->u.alias.name);
        MsBuf targets = {0};
        for (uint32_t i = 0; i < d->u.alias.targets.len; i++) {
            ms_buf_puts(&targets, i == 0 ? "" : " | ");
            facts_put_type_text(&targets, names, d->u.alias.targets.ptr[i]);
        }
        ms_buf_putc(body, ']');
        facts_put_tail_text(body, "", 0, &targets, "");
        ms_buf_free(&targets);
        return;
    }
    case MS_D_IMPL:
        facts_put_impl_name(&row->name, names, d);
        break;
    default:
        ms_buf_put(&row->name, d->u.test.name.ptr, d->u.test.name.len);
        tries = facts_tries_of((MsParams){0}, d->u.test.body);
        break;
    }
    ms_buf_putc(body, ']');
    facts_put_tail(body, names, result, "", tries, "");
}

static void facts_fill_method(FactsRow *row, const MsNames *names, const MsDecl *impl, const MsMethod *m) {
    facts_put_impl_name(&row->name, names, impl);
    ms_buf_putc(&row->name, '.');
    facts_put_str(&row->name, names, m->func.name);
    ms_buf_puts(&row->body, ", \"slots\": ");
    facts_put_params(&row->body, names, m->func.params, NULL);
    const char *mode = "borrow";
    if (m->mutating) {
        mode = "var";
    } else if (m->consuming) {
        mode = "move";
    }
    facts_put_tail(&row->body, names, m->func.result, mode, facts_tries_of(m->func.params, m->func.body), "");
}

/* `"field": ["a", "b"]` for `count` strings; `key_prefix`, when set, goes in front of each. */
static void facts_put_strings(MsBuf *out, const char *field, const MsStr *list, uint32_t count, const char *key_prefix) {
    ms_buf_printf(out, "\"%s\": [", field);
    for (uint32_t i = 0; i < count; i++) {
        MsBuf text = {0};
        if (key_prefix != NULL) {
            ms_buf_puts(&text, key_prefix);
        }
        ms_buf_put(&text, list[i].ptr, list[i].len);
        ms_buf_puts(out, i == 0 ? "" : ", ");
        facts_put_json_buf(out, &text);
        ms_buf_free(&text);
    }
    ms_buf_putc(out, ']');
}

/* How a character changes the nesting of brackets in a type text. */
static int facts_nest(char ch) {
    if (ch == '[' || ch == '(') {
        return 1;
    }
    if (ch == ']' || ch == ')') {
        return -1;
    }
    return 0;
}

/* The E of a function type `fn(...) Result[T, E]`, as crates/ms-tooling/src/facts.rs `error_type` reads it. */
static MsStr facts_error_type(MsStr ty) {
    const MsStr none = {ty.ptr + ty.len, 0};
    if (ty.len < 3 || memcmp(ty.ptr, "fn(", 3) != 0) {
        return none;
    }
    uint32_t at = 3;
    for (int depth = 1; at < ty.len && depth > 0; at++) {
        depth += facts_nest(ty.ptr[at]);
    }
    while (at < ty.len && ty.ptr[at] == ' ') {
        at++;
    }
    if (ty.len - at < 8 || memcmp(ty.ptr + at, "Result[", 7) != 0 || ty.ptr[ty.len - 1] != ']') {
        return none;
    }
    int depth = 0;
    for (uint32_t i = at + 7; i + 1 < ty.len; i++) {
        depth += facts_nest(ty.ptr[i]);
        if (ty.ptr[i] != ',' || depth != 0) {
            continue;
        }
        uint32_t from = i + 1;
        while (from < ty.len && ty.ptr[from] == ' ') {
            from++;
        }
        return (MsStr){ty.ptr + from, ty.len - 1 - from};
    }
    return none;
}

/* The `ty`, `error`, `exported` and `label` fields (`label` is "Receiver.method" for a method). Only a function has a type here: the other kinds print "". */
static void facts_put_meta(MsBuf *out, const MsCheck *c, MsModId m, const MsDecl *d, const MsBuf *label) {
    MsBuf ty = {0};
    const MsSymId sym = d != NULL && d->kind == MS_D_FN ? ms_decl_own_symbol(c, m, d) : MS_NONE;
    if (sym != MS_NONE && c->syms.ty[sym] != MS_TY_NONE) {
        ms_ty_show(&ty, c->names, &c->tys, c->syms.ty[sym]);
    }
    const MsStr error = facts_error_type((MsStr){ty.data == NULL ? "" : (const char *)ty.data, (uint32_t)ty.len});
    MsBuf text = {0};
    ms_buf_put(&text, error.ptr, error.len);
    ms_buf_puts(out, ", \"ty\": ");
    facts_put_json_buf(out, &ty);
    ms_buf_puts(out, ", \"error\": ");
    facts_put_json_buf(out, &text);
    ms_buf_printf(out, ", \"exported\": %s", d != NULL && d->is_exported ? "true" : "false");
    ms_buf_puts(out, ", \"label\": ");
    if (label == NULL) {
        ms_buf_puts(out, "\"\"");
    } else {
        facts_put_json_buf(out, label);
    }
    ms_buf_free(&text);
    ms_buf_free(&ty);
}

static int facts_str_compare(const void *a, const void *b) {
    const MsStr x = *(const MsStr *)a, y = *(const MsStr *)b;
    const uint32_t common = x.len < y.len ? x.len : y.len;
    const int order = common == 0 ? 0 : memcmp(x.ptr, y.ptr, common);
    if (order != 0) {
        return order;
    }
    return (x.len > y.len) - (x.len < y.len);
}

/* `[{"file", "paths"}]`: the module's import paths, sorted and unique. */
static void facts_put_imports(MsBuf *out, const MsModule *module, const char *file, size_t file_len) {
    MsBuf paths = {0};
    for (uint32_t i = 0; i < module->nimports; i++) {
        MsStr *slot = ms_buf_push(&paths, sizeof *slot);
        *slot = module->imports[i].path;
    }
    MsStr *items = ms_buf_items(&paths);
    const size_t count = paths.len / sizeof *items;
    if (count > 1) {
        qsort(items, count, sizeof *items, facts_str_compare);
    }
    ms_buf_puts(out, "[{\"file\": ");
    facts_put_json(out, file, file_len);
    ms_buf_puts(out, ", \"paths\": [");
    const char *sep = "";
    for (size_t i = 0; i < count; i++) {
        if (i > 0 && facts_str_compare(&items[i - 1], &items[i]) == 0) {
            continue;
        }
        ms_buf_puts(out, sep);
        facts_put_json(out, items[i].ptr, items[i].len);
        sep = ", ";
    }
    ms_buf_puts(out, "]}]");
    ms_buf_free(&paths);
}

static bool facts_has_default(MsParams params) {
    for (uint32_t i = 0; i < params.len; i++) {
        if (params.ptr[i]->def != NULL) {
            return true;
        }
    }
    return false;
}

/* The effect columns of one entity. A function the effect scan cannot see through completely, or
 * one it does not cover (methods, tests, impls), prints empty lists and `"effects_known": false`.
 * `calls` lists the project functions the body calls, as entity keys: a function with a method or
 * interface call or an implicit `close` is partial, so its calls are never printed short. */
static void facts_put_effects(MsBuf *out, const MsDecl *d, const MsEntityEffects *rows, uint32_t nrows, const char *file) {
    const MsEntityEffects *found = NULL;
    for (uint32_t r = 0; r < nrows; r++) {
        found = rows[r].decl == d ? &rows[r] : found;
    }
    const bool scanned = d != NULL && (d->kind == MS_D_FN || d->kind == MS_D_CONST);
    const bool declaration = d != NULL && !scanned && d->kind != MS_D_IMPL && d->kind != MS_D_TEST &&
                             !(d->kind == MS_D_TYPE && facts_has_default(d->u.type.fields)); /* a default runs code */
    if (found == NULL || found->partial) {
        ms_buf_printf(out, "\"effects\": [], \"reach\": [], \"permits\": [], \"calls\": [], \"effects_known\": %s",
                      declaration ? "true" : "false");
        return;
    }
    facts_put_strings(out, "effects", found->effects, found->neffects, NULL);
    ms_buf_puts(out, ", ");
    facts_put_strings(out, "reach", found->effects, found->neffects, NULL);
    ms_buf_puts(out, ", ");
    facts_put_strings(out, "permits", found->permits, found->npermits, NULL);
    ms_buf_puts(out, ", ");
    MsBuf prefix = {0};
    ms_buf_printf(&prefix, "%s#fn#", file);
    ms_buf_putc(&prefix, '\0');
    facts_put_strings(out, "calls", found->calls, found->ncalls, prefix.data);
    ms_buf_free(&prefix);
    ms_buf_puts(out, ", \"effects_known\": true");
}

void ms_dump_module_facts(MsBuf *out, MsCheck *c, MsModId m, MsStr text) {
    const MsModuleRow *row = &c->mods[m];
    const MsModule *module = row->syntax;
    const MsNames *names = c->names;
    MsBuf file = {0};
    facts_put_str(&file, names, row->path);
    ms_buf_putc(&file, '\0');
    MsBuf rows = {0};
    uint32_t total_lines = 1; /* the lines of the source, as the Rust side counts them: newlines plus one */
    for (uint32_t i = 0; i < text.len; i++) {
        total_lines += text.ptr[i] == '\n' ? 1 : 0;
    }
    MsArena scratch = {0};
    FactsOwn own = {.check = c, .module = m, .classifier = ms_classifier_new(c)};
    ms_classifier_mark_methods(own.classifier, c->mods[m].facts == NULL ? NULL : c->mods[m].facts->methods);
    uint32_t neffects = 0;
    const MsEntityEffects *effect_rows = ms_effect_facts(&scratch, c, m, text, &neffects);
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        if (d->synthetic && d->kind == MS_D_INTERFACE) {
            continue;
        }
        FactsRow *fact = facts_add_row(&rows, names, file.data, facts_kind_of(d),
                                       d->kind == MS_D_IMPL ? facts_impl_line(module, names, i) : d->pos.line);
        facts_fill_decl(fact, names, &own, d);
        facts_seal_key(fact);
        facts_put_effects(&fact->effects, d, effect_rows, neffects, file.data);
        facts_put_meta(&fact->meta, c, m, d, NULL);
        fact->first = d->pos.line;
        const uint32_t decl_last = i + 1 < module->ndecls ? module->decls[i + 1]->pos.line - 1 : total_lines;
        fact->last = decl_last;
        if (d->kind != MS_D_IMPL) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            const MsMethod *meth = d->u.impl.methods.ptr[k];
            FactsRow *method = facts_add_row(&rows, names, file.data, "method", meth->pos.line);
            facts_fill_method(method, names, d, meth);
            facts_seal_key(method);
            facts_put_effects(&method->effects, NULL, effect_rows, neffects, file.data);
            MsBuf label = {0};
            facts_put_str(&label, names, d->u.impl.receiver->kind == MS_TYPE_NAMED ? d->u.impl.receiver->name : 0);
            ms_buf_putc(&label, '.');
            facts_put_str(&label, names, meth->func.name);
            facts_put_meta(&method->meta, c, m, NULL, &label);
            ms_buf_free(&label);
            method->first = meth->pos.line;
            method->last = k + 1 < d->u.impl.methods.len ? d->u.impl.methods.ptr[k + 1]->pos.line - 1 : decl_last;
        }
    }
    FactsRow *items = ms_buf_items(&rows);
    const size_t count = rows.len / sizeof *items;
    qsort(items, count, sizeof *items, facts_compare_rows);
    ms_buf_puts(out, "{\n  \"entities\": [");
    bool first = true;
    for (size_t i = 0; i < count; i++) {
        if (i + 1 < count && items[i].key.len == items[i + 1].key.len && memcmp(items[i].key.data, items[i + 1].key.data, items[i].key.len) == 0) {
            continue; /* impl blocks of one type share a key: the last block prints, as the Rust map keeps it */
        }
        ms_buf_puts(out, first ? "\n    " : ",\n    ");
        first = false;
        ms_buf_puts(out, "{\"key\": ");
        facts_put_json_buf(out, &items[i].key);
        ms_buf_puts(out, ", \"file\": ");
        facts_put_json(out, file.data, file.len - 1);
        ms_buf_printf(out, ", \"kind\": \"%s\", \"name\": ", items[i].kind);
        facts_put_json_buf(out, &items[i].name);
        ms_buf_printf(out, ", \"line\": %u, \"scopes\": %u, \"ownership_known\": %s, \"external\": [], \"first\": %u, \"last\": %u, ",
                      items[i].line, items[i].scopes, items[i].own_known ? "true" : "false", items[i].first, items[i].last);
        ms_buf_put(out, items[i].effects.data, items[i].effects.len);
        ms_buf_put(out, items[i].meta.data, items[i].meta.len);
        ms_buf_put(out, items[i].body.data, items[i].body.len);
        ms_buf_putc(out, '}');
    }
    ms_buf_puts(out, "\n  ],\n  \"imports\": ");
    facts_put_imports(out, module, file.data, file.len - 1);
    ms_buf_puts(out, ", \"flows\": []\n}\n");
    for (size_t i = 0; i < count; i++) {
        ms_buf_free(&items[i].name);
        ms_buf_free(&items[i].key);
        ms_buf_free(&items[i].body);
        ms_buf_free(&items[i].effects);
        ms_buf_free(&items[i].meta);
    }
    ms_arena_free(&scratch);
    ms_classifier_free(own.classifier);
    ms_buf_free(&rows);
    ms_buf_free(&file);
}

/* The builtin kinds the typed lint rules ask about; any other type is "Other". A node with type arguments also
 * names the kind of the first ("arg"). */
static const char *nodes_kind(const MsTyTable *tys, MsTy ty) {
    switch (ms_ty_builtin(tys, ty)) {
    case MS_BI_OPTIONAL: return "Optional";
    case MS_BI_RESULT: return "Result";
    case MS_BI_LIST: return "List";
    case MS_BI_MAP: return "Map";
    case MS_BI_SET: return "Set";
    case MS_BI_BYTES: return "Bytes";
    case MS_BI_INT: return "Int";
    case MS_BI_FLOAT: return "Float";
    case MS_BI_BOOL: return "Bool";
    case MS_BI_STRING: return "String";
    case MS_BI_VOID: return "Void";
    case MS_BI_PROMISE: return "Promise";
    default: return "Other";
    }
}

void ms_dump_module_nodes(MsBuf *out, const MsCheck *c, MsModId m) {
    const MsFacts *facts = c->mods[m].facts;
    ms_buf_puts(out, "{\"nodes\": [");
    const char *sep = "";
    for (uint32_t id = 0; facts != NULL && id <= facts->node_count; id++) {
        if (facts->expr_ty[id] == MS_TY_NONE) {
            continue;
        }
        const MsTy ty = facts->expr_ty[id];
        ms_buf_printf(out, "%s{\"id\": %u, \"kind\": \"%s\"", sep, id, nodes_kind(&c->tys, ty));
        if (c->tys.nargs[ty] > 0) {
            /* The first type argument: the payload of a Result or Optional, the element of a List. */
            ms_buf_printf(out, ", \"arg\": \"%s\"", nodes_kind(&c->tys, ms_ty_args(&c->tys, ty)[0]));
        }
        ms_buf_putc(out, '}');
        sep = ", ";
    }
    ms_buf_puts(out, "]}\n");
}
