/* Canonical text form of the checker tables, compared with the Rust checker's. */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/dump.h"
#include "ms/effects.h"
#include "ms/facts.h"

static const MsCheck *g_sort;

static int by_symbol_name(const void *a, const void *b) {
    MsStr x = ms_name(g_sort->names, g_sort->syms.name[*(const MsSymId *)a]);
    MsStr y = ms_name(g_sort->names, g_sort->syms.name[*(const MsSymId *)b]);
    uint32_t n = x.len < y.len ? x.len : y.len;
    int r = memcmp(x.ptr, y.ptr, n);
    return r != 0 ? r : (x.len > y.len) - (x.len < y.len);
}

static void put_name(MsBuf *out, const MsCheck *c, MsSym s) {
    MsStr n = ms_name(c->names, s);
    ms_buf_put(out, n.ptr, n.len);
}

static const char *sym_kind_text(MsSymKind kind) {
    switch (kind) {
    case MS_SYM_FN: return " fn";
    case MS_SYM_ALIAS: return " alias";
    case MS_SYM_TYPE: return " type";
    }
    return " type";
}

void ms_dump_std_tables(MsBuf *out, const MsCheck *c) {
    for (uint32_t m = 0; m < c->nmods; m++) {
        const MsModule *mod = c->mods[m].syntax;
        for (uint32_t i = 0; i < mod->ndecls; i++) {
            const MsDecl *d = mod->decls[i];
            if (d->kind != MS_D_TYPE || !d->u.type.external) {
                continue;
            }
            uint32_t s = ms_map_get(&c->std_types, d->u.type.name);
            ms_buf_puts(out, "extern ");
            put_name(out, c, c->mods[m].path);
            ms_buf_putc(out, ' ');
            put_name(out, c, d->u.type.name);
            ms_buf_puts(out, " id=");
            put_name(out, c, c->syms.id[s]);
            ms_buf_printf(out, " export=%s vars=%u\n", c->syms.is_exported[s] ? "true" : "false", c->syms.nvars[s]);
        }
    }
    for (uint32_t m = 0; m < c->nmods; m++) {
        if (c->mods[m].source) {
            continue;
        }
        ms_buf_puts(out, "module ");
        put_name(out, c, c->mods[m].path);
        ms_buf_putc(out, '\n');
        uint32_t n = c->mods[m].norder;
        MsSymId *rows = malloc(sizeof *rows * (n + 1));
        uint32_t k = 0;
        for (uint32_t i = 0; i < n; i++) {
            MsSymId s = c->mods[m].order[i];
            if (c->syms.is_exported[s] && c->syms.native[s] != MS_NATIVE_SOURCE) {
                rows[k++] = s;
            }
        }
        g_sort = c;
        qsort(rows, k, sizeof *rows, by_symbol_name);
        for (uint32_t i = 0; i < k; i++) {
            MsSymId s = rows[i];
            ms_buf_puts(out, "  ");
            put_name(out, c, c->syms.name[s]);
            ms_buf_puts(out, sym_kind_text(c->syms.kind[s]));
            ms_buf_puts(out, " export=true id=");
            put_name(out, c, c->syms.id[s]);
            ms_buf_puts(out, " native=");
            switch (c->syms.native[s]) {
            case MS_NATIVE_CONTRACT: ms_buf_puts(out, "contract"); break;
            case MS_NATIVE_EXTERN: ms_buf_puts(out, "extern:"); put_name(out, c, c->syms.native_name[s]); break;
            default: ms_buf_puts(out, "builtin:"); put_name(out, c, c->syms.native_name[s]); break;
            }
            ms_buf_printf(out, " vars=%u\n", c->syms.nvars[s]);
        }
        free(rows);
    }
}

/* ---- the declared types of one module ---- */

static void put_type(MsBuf *out, const MsCheck *c, MsTy ty) {
    ms_ty_show(out, c->names, &c->tys, ty);
}

static void put_param(MsBuf *out, const MsCheck *c, const MsTyParam *p) {
    put_name(out, c, p->name);
    ms_buf_puts(out, ": ");
    ms_buf_puts(out, (p->flags & MS_PARAM_VAR) != 0 ? "var " : "");
    ms_buf_puts(out, (p->flags & MS_PARAM_MOVE) != 0 ? "move " : "");
    put_type(out, c, p->ty);
}

static void put_variable(MsBuf *out, const MsCheck *c, MsTy var) {
    const MsVarInfo *info = var < c->var_info_cap ? &c->var_info[var] : NULL;
    ms_buf_puts(out, "  var ");
    put_name(out, c, c->tys.name[var]);
    ms_buf_puts(out, " default=");
    if (info != NULL && info->def != MS_TY_NONE) {
        put_type(out, c, info->def);
    } else {
        ms_buf_putc(out, '-');
    }
    ms_buf_puts(out, " bounds=");
    for (uint32_t i = 0; info != NULL && i < info->nbounds; i++) {
        ms_buf_puts(out, i == 0 ? "" : ",");
        put_type(out, c, info->bounds[i]);
    }
    ms_buf_putc(out, '\n');
}

static void put_symbol_types(MsBuf *out, const MsCheck *c, MsSymId s) {
    ms_buf_puts(out, "sym ");
    put_name(out, c, c->syms.name[s]);
    ms_buf_puts(out, ": ");
    if (c->syms.ty[s] != MS_TY_NONE) {
        put_type(out, c, c->syms.ty[s]);
    } else {
        ms_buf_putc(out, '-');
    }
    ms_buf_putc(out, '\n');
    uint32_t nvars = 0;
    const MsTy *vars = ms_sym_vars(c, s, &nvars);
    for (uint32_t i = 0; i < nvars; i++) {
        put_variable(out, c, vars[i]);
    }
    const MsDef *def = s < c->defs_cap ? &c->defs[s] : NULL;
    for (uint32_t i = 0; def != NULL && i < def->nfields; i++) {
        ms_buf_puts(out, "  field ");
        put_param(out, c, &def->fields[i]);
        ms_buf_putc(out, '\n');
    }
    for (uint32_t i = 0; def != NULL && i < def->ncases; i++) {
        ms_buf_puts(out, "  case ");
        put_name(out, c, def->cases[i].name);
        ms_buf_putc(out, '(');
        for (uint32_t k = 0; k < def->cases[i].nfields; k++) {
            ms_buf_puts(out, k == 0 ? "" : ", ");
            put_param(out, c, &def->cases[i].fields[k]);
        }
        ms_buf_puts(out, ")\n");
    }
}

/* Marks the references written in a type-parameter list: the Rust checker resolves them again for
 * the operations of an implementation, so their entries are not the declaration pass's. */
static void mark_type_ref(uint8_t *skip, uint32_t count, const MsTypeRef *t) {
    if (t == NULL) {
        return;
    }
    if (t->id < count) {
        skip[t->id] = 1;
    }
    for (uint32_t i = 0; i < t->args.len; i++) {
        mark_type_ref(skip, count, t->args.ptr[i]);
    }
    for (uint32_t i = 0; i < t->params.len; i++) {
        mark_type_ref(skip, count, t->params.ptr[i]->ty);
    }
    mark_type_ref(skip, count, t->result);
}

static void mark_type_params(uint8_t *skip, uint32_t count, const MsDecl *d) {
    const MsTypeParams *params = NULL;
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: params = &d->u.fn.type_params; break;
    case MS_D_TYPE: params = &d->u.type.type_params; break;
    case MS_D_ENUM: params = &d->u.enumeration.type_params; break;
    case MS_D_ALIAS: params = &d->u.alias.type_params; break;
    case MS_D_INTERFACE: params = &d->u.iface.type_params; break;
    case MS_D_CONST:
    case MS_D_IMPL:
    case MS_D_TEST: return;
    }
    for (uint32_t i = 0; i < params->len; i++) {
        mark_type_ref(skip, count, params->ptr[i]->def);
        for (uint32_t k = 0; k < params->ptr[i]->bounds.len; k++) {
            mark_type_ref(skip, count, params->ptr[i]->bounds.ptr[k]);
        }
    }
}

void ms_dump_module_types(MsBuf *out, const MsCheck *c, MsModId m) {
    const MsModuleRow *row = &c->mods[m];
    for (uint32_t i = 0; i < row->norder; i++) {
        const MsSymId s = row->order[i];
        const MsDecl *d = c->syms.decl[s];
        /* A declaration whose name another symbol took is not the module's symbol. */
        const bool bound = ms_map_get(&row->names, c->syms.name[s]) == s;
        if (d != NULL && d->kind != MS_D_CONST && bound) {
            put_symbol_types(out, c, s);
        }
    }
    const MsFacts *facts = row->facts;
    if (facts == NULL) {
        return;
    }
    uint8_t *skip = calloc((size_t)facts->node_count + 1, 1);
    for (uint32_t i = 0; skip != NULL && i < row->syntax->ndecls; i++) {
        mark_type_params(skip, facts->node_count + 1, row->syntax->decls[i]);
    }
    for (uint32_t id = 0; skip != NULL && id <= facts->node_count; id++) {
        if (facts->type_ref_ty[id] != MS_TY_NONE && skip[id] == 0) {
            ms_buf_printf(out, "typeref %u ", id);
            put_type(out, c, facts->type_ref_ty[id]);
            ms_buf_putc(out, '\n');
        }
    }
    free(skip);
}

/* ---- function bodies ---- */

static void dump_expr(MsBuf *out, const MsCheck *c, const MsFacts *facts, const MsExpr *e);

/* The line of one expression: its node id and the type the checker gave it. */
static void dump_expr_line(MsBuf *out, const MsCheck *c, const MsFacts *facts, const MsExpr *e) {
    ms_buf_printf(out, "expr %u ", e->id);
    // A node the checker never typed (the `_` of a match arm) is `-`.
    if (facts->expr_ty[e->id] == MS_TY_NONE) {
        ms_buf_putc(out, '-');
    } else {
        ms_ty_show(out, c->names, &c->tys, facts->expr_ty[e->id]);
    }
    ms_buf_putc(out, '\n');
}

static void dump_expr(MsBuf *out, const MsCheck *c, const MsFacts *facts, const MsExpr *e) {
    dump_expr_line(out, c, facts, e);
    switch ((MsExprKind)e->kind) {
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            if (e->u.text.ptr[i].expr != NULL) {
                dump_expr(out, c, facts, e->u.text.ptr[i].expr);
            }
        }
        break;
    case MS_E_UNARY: dump_expr(out, c, facts, e->u.bin.left); break;
    case MS_E_MEMBER: dump_expr(out, c, facts, e->u.member.left); break;
    case MS_E_BINARY:
        dump_expr(out, c, facts, e->u.bin.left);
        dump_expr(out, c, facts, e->u.bin.right);
        break;
    case MS_E_CALL:
        for (uint32_t i = 0; i < e->u.call.args.len; i++) {
            dump_expr(out, c, facts, e->u.call.args.ptr[i].value);
        }
        break;
    case MS_E_MATCH:
        dump_expr(out, c, facts, e->u.match.scrutinee);
        for (uint32_t i = 0; i < e->u.match.arms.len; i++) {
            const MsArm *arm = e->u.match.arms.ptr[i];
            dump_expr_line(out, c, facts, arm->path); /* a pattern: its parts are not expressions */
            if (arm->value != NULL) {
                dump_expr(out, c, facts, arm->value);
            }
        }
        break;
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_NAME:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA: break;
    }
}

static void dump_stmts(MsBuf *out, const MsCheck *c, const MsFacts *facts, const MsStmts *body) {
    for (uint32_t k = 0; k < body->len; k++) {
        const MsStmt *s = body->ptr[k];
        switch ((MsStmtKind)s->kind) {
        case MS_S_BIND: dump_expr(out, c, facts, s->u.bind.value); break;
        case MS_S_RETURN:
        case MS_S_CALL:
            if (s->u.expr != NULL) {
                dump_expr(out, c, facts, s->u.expr);
            }
            break;
        case MS_S_IF:
            dump_expr(out, c, facts, s->u.branch.cond);
            dump_stmts(out, c, facts, &s->u.branch.body);
            dump_stmts(out, c, facts, &s->u.branch.else_body);
            break;
        case MS_S_WHILE:
            dump_expr(out, c, facts, s->u.loop.cond);
            dump_stmts(out, c, facts, &s->u.loop.body);
            break;
        case MS_S_ASSIGN: dump_expr(out, c, facts, s->u.assign.value); break;
        case MS_S_FOR: // a call as the iterable is untyped itself (a range, or a function returning a list); its arguments are
            for (uint32_t i = 0; s->u.each.iter->kind == MS_E_CALL && i < s->u.each.iter->u.call.args.len; i++) {
                dump_expr(out, c, facts, s->u.each.iter->u.call.args.ptr[i].value);
            }
            dump_stmts(out, c, facts, &s->u.each.body);
            break;
        case MS_S_BREAK:
        case MS_S_CONTINUE: break;
        }
    }
}

/* The diagnostics on lines `first` up to (not including) `end`, one `diag L:C: message` line each:
 * a function owns the lines from its own to the next declaration's, as the Rust oracle attributes
 * them. */
static void dump_function_diags(MsBuf *out, const MsModuleRow *row, uint32_t first, uint32_t end) {
    for (uint32_t k = 0; k < row->ndiags; k++) {
        const MsDiag *diag = &row->diags[k].diag;
        if (diag->pos.line >= first && diag->pos.line < end) {
            ms_buf_printf(out, "diag %u:%u: %.*s\n", diag->pos.line, diag->pos.column, (int)diag->message.len,
                          diag->message.ptr);
        }
    }
}

static uint32_t dump_decl_end(const MsModuleRow *row, uint32_t index) {
    return index + 1 < row->syntax->ndecls ? row->syntax->decls[index + 1]->pos.line : UINT32_MAX;
}

/* Calls `visit` for each method an impl of the module wrote, with the lines it owns: from its name to
 * the next method of the impl, or the next declaration. */
typedef void (*DumpMethodFn)(void *state, const MsMethod *method, uint32_t first, uint32_t end);

static void dump_each_method(const MsModuleRow *row, DumpMethodFn visit, void *state) {
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind != MS_D_IMPL) {
            continue;
        }
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            const MsMethod *method = d->u.impl.methods.ptr[k];
            const uint32_t end = k + 1 < d->u.impl.methods.len ? d->u.impl.methods.ptr[k + 1]->pos.line
                                                                : dump_decl_end(row, i);
            visit(state, method, method->pos.line, end);
        }
    }
}

typedef struct DumpBodies {
    MsBuf *out;
    const MsCheck *c;
    const MsFacts *facts;
    const MsModuleRow *row;
    const bool *declined;
    bool ownership;
} DumpBodies;

static void dump_method_body(void *state, const MsMethod *method, uint32_t first, uint32_t end) {
    const DumpBodies *d = state;
    if (!d->facts->body_checked[method->id]) {
        return;
    }
    ms_buf_printf(d->out, "fn %u:%u%s\n", method->pos.line, method->pos.column,
                  !d->ownership && d->declined != NULL && d->declined[method->id] ? " ownership-declined" : "");
    dump_function_diags(d->out, d->row, first, end);
    if (!d->ownership) {
        dump_stmts(d->out, d->c, d->facts, &method->func.body);
    }
}

void ms_dump_module_bodies(MsBuf *out, const MsCheck *c, MsModId m, const bool *declined) {
    const MsModuleRow *row = &c->mods[m];
    const MsFacts *facts = row->facts;
    for (uint32_t i = 0; facts != NULL && facts->body_checked != NULL && i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if ((d->kind != MS_D_FN && d->kind != MS_D_CONST) || !facts->body_checked[d->id]) {
            continue;
        }
        const bool constant = d->kind == MS_D_CONST;
        ms_buf_printf(out, "%s %u:%u%s\n", constant ? "const" : "fn", d->pos.line, d->pos.column,
                      declined != NULL && declined[d->id] ? " ownership-declined" : "");
        dump_function_diags(out, row, d->pos.line, dump_decl_end(row, i));
        if (constant) {
            dump_expr(out, c, facts, d->u.konst.value);
        } else {
            dump_stmts(out, c, facts, &d->u.fn.body);
        }
    }
    if (facts != NULL && facts->body_checked != NULL) {
        DumpBodies state = {.out = out, .c = c, .facts = facts, .row = row, .declined = declined};
        dump_each_method(row, dump_method_body, &state);
    }
}

void ms_dump_module_ownership(MsBuf *out, const MsCheck *c, MsModId m) {
    const MsModuleRow *row = &c->mods[m];
    const MsFacts *facts = row->facts;
    for (uint32_t i = 0; facts != NULL && facts->body_checked != NULL && i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind != MS_D_FN || !facts->body_checked[d->id]) {
            continue;
        }
        ms_buf_printf(out, "fn %u:%u\n", d->pos.line, d->pos.column);
        dump_function_diags(out, row, d->pos.line, dump_decl_end(row, i));
    }
    if (facts != NULL && facts->body_checked != NULL) {
        DumpBodies state = {.out = out, .c = c, .facts = facts, .row = row, .ownership = true};
        dump_each_method(row, dump_method_body, &state);
    }
}

/* `word a,b,c`, the names sorted by the caller; nothing for an empty list. */
static void dump_names(MsBuf *out, const char *word, const MsStr *names, uint32_t count) {
    if (count == 0) {
        return;
    }
    ms_buf_printf(out, "%s ", word);
    for (uint32_t k = 0; k < count; k++) {
        ms_buf_printf(out, "%s%.*s", k == 0 ? "" : ",", (int)names[k].len, names[k].ptr);
    }
    ms_buf_printf(out, "\n");
}

void ms_dump_module_effects(MsBuf *out, const MsCheck *c, MsModId m, MsStr text) {
    const MsModuleRow *row = &c->mods[m];
    const MsFacts *facts = row->facts;
    MsArena scratch = {0};
    uint32_t nrows = 0;
    const MsEntityEffects *rows = ms_effect_facts(&scratch, c, m, text, &nrows);
    for (uint32_t i = 0; facts != NULL && facts->body_checked != NULL && i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if ((d->kind != MS_D_FN && d->kind != MS_D_CONST) || !facts->body_checked[d->id]) {
            continue;
        }
        const MsEntityEffects *facts_row = NULL;
        for (uint32_t r = 0; r < nrows; r++) {
            facts_row = rows[r].decl == d ? &rows[r] : facts_row;
        }
        if (facts_row == NULL || facts_row->partial) {
            continue; // what it reaches is not fully visible yet: not claimed
        }
        const MsScanNode node = ms_effect_scan_decl(&scratch, c, m, d);
        ms_buf_printf(out, "%s %u:%u\n", d->kind == MS_D_CONST ? "const" : "fn", d->pos.line, d->pos.column);
        for (uint32_t k = 0; k < node.nedges; k++) {
            // A method has no symbol: the oracle's serial method id is normalized to `method` too.
            const MsStr name = node.edges[k].callee >= c->syms.count
                                   ? (MsStr){"method", 6}
                                   : ms_name(c->names, c->syms.name[node.edges[k].callee]);
            ms_buf_printf(out, "edge %.*s %u:%u\n", (int)name.len, name.ptr, node.edges[k].pos.line,
                          node.edges[k].pos.column);
        }
        dump_names(out, "reach", facts_row->effects, facts_row->neffects);
        dump_names(out, "permits", facts_row->permits, facts_row->npermits);
    }
    ms_arena_free(&scratch);
}
