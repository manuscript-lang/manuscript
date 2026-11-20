/* `ms check FILE.ms [--json]` in C (ms_check_run; the driver and the Manuscript front call it). The command reads the file with the project modules it imports, runs the
 * checker passes the C side has (names, types, bodies, ownership, unused bindings) over every module, and
 * reports `Checked FILE` (or the empty `--json` document) when nothing is wrong. Anything else is handed to
 * the Rust `ms`: another flag or target, a project the C loader does not read, a function or declaration the
 * C passes do not cover (their silence proves nothing), and every diagnostic, which the Rust command renders. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/check_run.h"
#include "ms/diag_render.h"
#include "ms/facts.h"
#include "ms/ownership.h"
#include "ms/program.h"
#include "ms/project.h"
#include "ms/stdlib.h"

/* Whether the checker's passes decided every function, constant and declaration of the module: a function
 * with a construct they do not handle has no `body_checked`, and an impl or test body is not read at all. */
static bool check_module_covered(const MsCheck *c, MsModId id) {
    const MsModuleRow *row = &c->mods[id];
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind == MS_D_IMPL || d->kind == MS_D_TEST) {
            return false;
        }
        const bool callable = (d->kind == MS_D_FN && !d->u.fn.external) || d->kind == MS_D_CONST;
        if (callable && !d->synthetic && (row->facts == NULL || !row->facts->body_checked[d->id])) {
            return false;
        }
    }
    return true;
}

/* A `// ms:` directive (effects) is read by a pass the C side does not run on a project yet. */
static bool check_has_directive(const MsGraphModule *module) {
    return module->length != 0 && strstr(module->source, "// ms:") != NULL;
}

static bool check_name_is(const MsCheck *c, MsSym name, const char *text) {
    const MsStr s = ms_name(c->names, name);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

static bool check_contains(MsStr text, const char *needle) {
    const size_t n = strlen(needle);
    for (size_t i = 0; i + n <= text.len; i++) {
        if (memcmp(text.ptr + i, needle, n) == 0) {
            return true;
        }
    }
    return false;
}

static const char *check_phase_name(MsPhase phase) {
    return phase == MS_PHASE_RESOLUTION ? "resolution" : "type";
}

static bool check_has_params(const MsParams *params) {
    for (uint32_t i = 0; i < params->len; i++) {
        if (params->ptr[i]->def != NULL) {
            return true;
        }
    }
    return false;
}

/* What the module uses that a C pass is still missing, or NULL. Each entry names a check the C checker has no
 * port of; `check-cmd-diff.sh` shows the files that need it, and an entry goes when its port lands. */
static const char *check_unported(const MsCheck *c, const MsModule *module) {
    bool exported = false, private_type = false;
    for (uint32_t i = 0; i < module->nimports; i++) {
        const MsSymId sym = ms_map_get(&c->std_types, module->imports[i].name);
        if (sym != MS_NONE && ms_is_prelude_symbol(c, sym)) {
            return "an import of a prelude name (redundant prelude import)";
        }
    }
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        exported = exported || d->is_exported;
        switch ((MsDeclKind)d->kind) {
        case MS_D_FN:
            if (d->u.fn.external) return "an extern function";
            if (d->u.fn.type_params.len != 0) return "a generic function";
            if (check_name_is(c, d->u.fn.name, "main")) return "the entry signature";
            break;
        case MS_D_CONST:
            if (check_name_is(c, d->u.konst.name, "main")) return "the entry signature";
            break;
        case MS_D_TYPE:
            if (d->u.type.external) return "an extern type";
            if (d->u.type.type_params.len != 0) return "a generic type";
            if (check_has_params(&d->u.type.fields)) return "a field default";
            private_type = private_type || !d->is_exported;
            break;
        case MS_D_ENUM:
            if (d->u.enumeration.type_params.len != 0) return "a generic type";
            private_type = private_type || !d->is_exported;
            break;
        case MS_D_ALIAS:
            if (d->u.alias.type_params.len != 0) return "a generic type";
            private_type = private_type || !d->is_exported;
            break;
        case MS_D_INTERFACE:
            if (d->u.iface.type_params.len != 0 || d->u.iface.methods.len == 0) return "a generic or empty interface";
            private_type = private_type || !d->is_exported;
            break;
        case MS_D_IMPL:
        case MS_D_TEST:
            break;
        }
    }
    return exported && private_type ? "a public signature that may expose a private type" : NULL;
}

int ms_check_run(const MsStdFile *std_files, uint32_t nstd, const char *target, bool json, MsBuf *out, MsBuf *err) {
    MsNames names;
    ms_names_init(&names);
    MsArena arena = {0};
    MsGraph graph;
    MsProjectError error = {0};
    int status = MS_CHECK_HANDOVER;
    const char *why = "the load";
    MsCheck check;
    bool have_check = false;
    MsArena std_syntax = {0};
    if (!ms_project_load(&arena, &names, target, &graph, &error) || graph.ndiagnostics != 0 || graph.count == 0) {
        goto done;
    }
    for (uint32_t i = 0; i < graph.count; i++) {
        if (check_has_directive(&graph.modules[i])) {
            why = "an effect directive";
            goto done;
        }
    }
    ms_check_init(&check, &names);
    have_check = true;
    MsStr load_error = {0};
    if (!ms_std_load(&check, &std_syntax, std_files, nstd, &load_error)) {
        goto done;
    }
    MsModId *ids = MS_NEW_N(&arena, MsModId, graph.count);
    bool *unchecked = MS_NEW_N(&arena, bool, graph.count);
    ms_graph_add_modules(&check, &names, &arena, &graph, ids);
    for (uint32_t i = 0; i < graph.count; i++) {
        why = check_unported(&check, &graph.modules[i].syntax);
        if (why != NULL) {
            goto done;
        }
    }
    why = "a module the passes left unchecked";
    if (ms_graph_check(&check, &graph, ids, unchecked) != 0) {
        goto done;
    }
    size_t total = 0;
    for (uint32_t i = 0; i < graph.count; i++) {
        ms_module_check_ownership(&check, ids[i]);
        ms_module_check_unused(&check, ids[i]);
        why = "a function or declaration no C pass covers";
        if (!check_module_covered(&check, ids[i])) {
            goto done;
        }
        total += check.mods[ids[i]].ndiags;
    }
    MsReport *reports = MS_NEW_N(&arena, MsReport, total + 1);
    size_t nreports = 0;
    for (uint32_t i = 0; i < graph.count; i++) {
        const MsModuleRow *row = &check.mods[ids[i]];
        const char *const shown = graph.source_root == NULL || ms_path_is_abs(graph.modules[i].name)
                                      ? graph.modules[i].name
                                      : MS_PATH_JOIN(&arena, graph.source_root, graph.modules[i].name);
        for (uint32_t k = 0; k < row->ndiags; k++) {
            reports[nreports++] = (MsReport){.diag = row->diags[k].diag,
                                             .file = graph.modules[i].name,
                                             .shown = shown,
                                             .phase = check_phase_name(row->diags[k].phase)};
        }
    }
    /* JSON diagnostics carry the machine-applicable `fix` the C passes do not all build yet, and the terminal
     * report names project modules in `add: import` suggestions the C hints do not read. */
    why = "a diagnostic in the JSON document (its fix is not built in C yet)";
    if (json && nreports != 0) {
        goto done;
    }
    why = "an import suggestion that reads the project's modules";
    for (size_t i = 0; i < nreports; i++) {
        const MsStr message = reports[i].diag.message;
        if (check_contains(message, "; add: import ")) {
            goto done;
        }
    }
    /* ms_render_text lists diagnostics in position order; the Rust command keeps the checker's order unless every
     * diagnostic is a syntax error. They agree when the checker's order already is position order. */
    why = "diagnostics not in position order";
    for (size_t i = 1; i < nreports; i++) {
        const MsPos a = reports[i - 1].diag.pos, b = reports[i].diag.pos;
        if (strcmp(reports[i - 1].file, reports[i].file) > 0 || (strcmp(reports[i - 1].file, reports[i].file) == 0 &&
                                                                  (a.line > b.line || (a.line == b.line && a.column > b.column)))) {
            goto done;
        }
    }
    if (nreports != 0) {
        why = "a diagnostic";
        if (json) {
            ms_render_json(out, reports, nreports);
        } else {
            ms_render_text(err, reports, nreports);
        }
        status = 1;
        goto done;
    }
    if (json) {
        ms_buf_puts(out, "{\n  \"format\": 1,\n  \"diagnostics\": []\n}\n");
    } else if (graph.project_root != NULL) {
        ms_buf_printf(out, "Checked %s (%u %s)\n", target, graph.count, graph.count == 1 ? "module" : "modules");
    } else {
        ms_buf_printf(out, "Checked %s\n", target);
    }
    status = 0;
done:
    if (status == MS_CHECK_HANDOVER && getenv("MS_DRIVER_TRACE") != NULL) {
        fprintf(stderr, "ms driver: check handover: %s\n", why);
    }
    if (have_check) {
        ms_check_free(&check);
    }
    ms_arena_free(&std_syntax);
    ms_arena_free(&arena);
    ms_names_free(&names);
    return status;
}
