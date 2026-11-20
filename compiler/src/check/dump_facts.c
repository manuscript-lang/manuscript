/* The fact model of one module as JSON: the document `tools/ms/views.ms` reads and
 * `ms-tooling-dev facts` prints from the Rust checker (crates/ms-tooling/src/collect.rs).
 * Stage 1 prints what the syntax tree gives: entity key, kind, name, line, slots, result, receiver
 * mode and try count. The fields that need checker columns (calls, effects, error type, passing
 * modes, referenced types, resource scopes, flows) are printed empty and are compared only once
 * their column exists (compiler/tests/facts-diff.sh). */
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"
#include "ms/facts.h"
#include "ms/walk.h"

typedef struct FactsRow {
    const char *kind;
    MsBuf name;
    MsBuf key;
    uint32_t line;
    MsBuf body; /* the JSON fields after `line`: slots, result, receiver, tries */
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

static void facts_put_slot(MsBuf *out, const MsNames *names, MsSym name, const MsTypeRef *ty, bool exclusive) {
    MsBuf text = {0};
    MsBuf label = {0};
    facts_put_str(&label, names, name);
    facts_put_type_text(&text, names, ty);
    ms_buf_puts(out, "{\"name\": ");
    facts_put_json_buf(out, &label);
    ms_buf_puts(out, ", \"ty\": ");
    facts_put_json_buf(out, &text);
    ms_buf_printf(out, ", \"exclusive\": %s, \"mode\": \"\", \"refs\": []}", exclusive ? "true" : "false");
    ms_buf_free(&text);
    ms_buf_free(&label);
}

static void facts_put_params(MsBuf *out, const MsNames *names, MsParams params) {
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < params.len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ", ");
        facts_put_slot(out, names, params.ptr[i]->name, params.ptr[i]->ty, params.ptr[i]->is_mutable);
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
static void facts_put_tail(MsBuf *out, const MsNames *names, const MsTypeRef *result, const char *receiver, uint32_t tries) {
    ms_buf_puts(out, ", \"result_ownership\": \"\", \"result_borrow\": false, \"receiver\": \"");
    ms_buf_puts(out, receiver);
    ms_buf_printf(out, "\", \"tries\": %u", tries);
    ms_buf_puts(out, ", \"result\": ");
    if (result == NULL) {
        ms_buf_puts(out, "null");
        return;
    }
    MsBuf text = {0};
    facts_put_type_text(&text, names, result);
    ms_buf_puts(out, "{\"name\": \"\", \"ty\": ");
    facts_put_json_buf(out, &text);
    ms_buf_puts(out, ", \"exclusive\": false, \"mode\": \"\", \"refs\": []}");
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
static void facts_put_inner_params(MsBuf *body, const MsNames *names, MsParams params) {
    MsBuf slots = {0};
    facts_put_params(&slots, names, params);
    ms_buf_put(body, slots.data + 1, slots.len - 2);
    ms_buf_free(&slots);
}

static void facts_fill_decl(FactsRow *row, const MsNames *names, const MsDecl *d) {
    MsBuf *body = &row->body;
    ms_buf_puts(body, ", \"slots\": [");
    const MsTypeRef *result = NULL;
    uint32_t tries = 0;
    switch (d->kind) {
    case MS_D_FN:
        facts_put_str(&row->name, names, d->u.fn.name);
        facts_put_inner_params(body, names, d->u.fn.params);
        result = d->u.fn.result;
        tries = facts_tries_of(d->u.fn.params, d->u.fn.body);
        break;
    case MS_D_TYPE:
        facts_put_str(&row->name, names, d->u.type.name);
        facts_put_inner_params(body, names, d->u.type.fields);
        break;
    case MS_D_ENUM:
        facts_put_str(&row->name, names, d->u.enumeration.name);
        facts_put_case_slots(body, names, d);
        ms_buf_putc(body, ']');
        facts_put_tail(body, names, NULL, "", 0);
        return;
    case MS_D_INTERFACE:
        facts_put_str(&row->name, names, d->u.iface.name);
        facts_put_method_slots(body, names, d);
        ms_buf_putc(body, ']');
        facts_put_tail(body, names, NULL, "", 0);
        return;
    case MS_D_CONST:
        facts_put_str(&row->name, names, d->u.konst.name);
        break;
    case MS_D_ALIAS:
        facts_put_str(&row->name, names, d->u.alias.name);
        break;
    case MS_D_IMPL:
        facts_put_impl_name(&row->name, names, d);
        break;
    default:
        ms_buf_put(&row->name, d->u.test.name.ptr, d->u.test.name.len);
        tries = facts_tries_of((MsParams){0}, d->u.test.body);
        break;
    }
    ms_buf_putc(body, ']');
    facts_put_tail(body, names, result, "", tries);
}

static void facts_fill_method(FactsRow *row, const MsNames *names, const MsDecl *impl, const MsMethod *m) {
    facts_put_impl_name(&row->name, names, impl);
    ms_buf_putc(&row->name, '.');
    facts_put_str(&row->name, names, m->func.name);
    ms_buf_puts(&row->body, ", \"slots\": ");
    facts_put_params(&row->body, names, m->func.params);
    const char *mode = "borrow";
    if (m->mutating) {
        mode = "var";
    } else if (m->consuming) {
        mode = "move";
    }
    facts_put_tail(&row->body, names, m->func.result, mode, facts_tries_of(m->func.params, m->func.body));
}

void ms_dump_module_facts(MsBuf *out, const MsCheck *c, MsModId m) {
    const MsModuleRow *row = &c->mods[m];
    const MsModule *module = row->syntax;
    const MsNames *names = c->names;
    MsBuf file = {0};
    facts_put_str(&file, names, row->path);
    ms_buf_putc(&file, '\0');
    MsBuf rows = {0};
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        if (d->synthetic && d->kind == MS_D_INTERFACE) {
            continue;
        }
        FactsRow *fact = facts_add_row(&rows, names, file.data, facts_kind_of(d),
                                       d->kind == MS_D_IMPL ? facts_impl_line(module, names, i) : d->pos.line);
        facts_fill_decl(fact, names, d);
        facts_seal_key(fact);
        if (d->kind != MS_D_IMPL) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            const MsMethod *meth = d->u.impl.methods.ptr[k];
            FactsRow *method = facts_add_row(&rows, names, file.data, "method", meth->pos.line);
            facts_fill_method(method, names, d, meth);
            facts_seal_key(method);
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
        ms_buf_printf(out, ", \"line\": %u, \"effects\": [], \"error\": \"\", \"scopes\": 0, \"calls\": [], \"external\": []", items[i].line);
        ms_buf_put(out, items[i].body.data, items[i].body.len);
        ms_buf_putc(out, '}');
    }
    ms_buf_puts(out, "\n  ],\n  \"imports\": [], \"flows\": []\n}\n");
    for (size_t i = 0; i < count; i++) {
        ms_buf_free(&items[i].name);
        ms_buf_free(&items[i].key);
        ms_buf_free(&items[i].body);
    }
    ms_buf_free(&rows);
    ms_buf_free(&file);
}

/* The builtin kinds the typed lint rules ask about; any other type is "Other". */
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
        ms_buf_printf(out, "%s{\"id\": %u, \"kind\": \"%s\"}", sep, id, nodes_kind(&c->tys, facts->expr_ty[id]));
        sep = ", ";
    }
    ms_buf_puts(out, "]}\n");
}
