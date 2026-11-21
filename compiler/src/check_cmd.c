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
#include "ms/check_run_state.h"
#include "ms/diag_render.h"
#include "ms/entry.h"
#include "ms/facts.h"
#include "ms/ownership.h"
#include "ms/program.h"
#include "ms/project.h"
#include "ms/stdlib.h"

/* Every default of the type's fields was typed by the body pass; a default it declined (a conversion Rust
 * rewrites) has no diagnostic here and stays with Rust. */
static bool check_defaults_covered(const MsModuleRow *row, const MsDecl *d) {
    for (uint32_t i = 0; i < d->u.type.fields.len; i++) {
        const MsExpr *def = d->u.type.fields.ptr[i]->def;
        if (def != NULL && (row->facts == NULL || row->facts->expr_ty == NULL || row->facts->expr_ty[def->id] == MS_TY_NONE)) {
            return false;
        }
    }
    return true;
}

/* Whether the checker's passes decided every function, constant and declaration of the module: a function
 * with a construct they do not handle has no `body_checked`, and an impl or test body is not read at all. */
static bool check_module_covered(const MsCheck *c, MsModId id) {
    const MsModuleRow *row = &c->mods[id];
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind == MS_D_IMPL) {
            return false;
        }
        if (d->kind == MS_D_TEST && (row->facts == NULL || !row->facts->body_checked[d->id])) {
            return false;
        }
        if (d->kind == MS_D_TYPE && !d->u.type.external && !check_defaults_covered(row, d)) {
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

/* What the module uses that a C pass is still missing, or NULL. Each entry names a check the C checker has no
 * port of; `check-cmd-diff.sh` shows the files that need it, and an entry goes when its port lands. */
static const char *check_unported(const MsCheck *c, const MsModule *module) {
    (void)c;
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        switch ((MsDeclKind)d->kind) {
        case MS_D_FN:
            if (d->u.fn.type_params.len != 0) return "a generic function";
            break;
        case MS_D_CONST:
            break;
        case MS_D_TYPE:
            if (d->u.type.type_params.len != 0) return "a generic type";
            break;
        case MS_D_ENUM:
            if (d->u.enumeration.type_params.len != 0) return "a generic type";
            break;
        case MS_D_ALIAS:
            if (d->u.alias.type_params.len != 0) return "a generic type";
            break;
        case MS_D_INTERFACE:
            if (d->u.iface.type_params.len != 0) return "a generic interface";
            break;
        case MS_D_IMPL:
        case MS_D_TEST:
            break;
        }
    }
    return NULL;
}


/* Loads the graph and the standard library and declares the modules. NULL, or what the C passes cannot answer. */
const char *ms_check_load(MsCheckRun *run, const MsStdFile *std_files, uint32_t nstd, const char *target) {
    MsProjectError error = {0};
    MsGraph *graph = &run->graph;
    if (!ms_project_load_packages(&run->arena, &run->names, target, graph, &error)) {
        return ms_project_error_is_unsupported(&error) ? "a project the loader does not read" : "the loader failed";
    }
    if (graph->ndiagnostics != 0) {
        run->load_failed = true;
        return NULL;
    }
    if (graph->count == 0) {
        return "an empty graph";
    }
    for (uint32_t i = 0; i < graph->count; i++) {
        if (check_has_directive(&graph->modules[i])) {
            return "an effect directive";
        }
    }
    ms_check_init(&run->check, &run->names);
    run->have_check = true;
    MsStr load_error = {0};
    if (!ms_std_load(&run->check, &run->std_syntax, std_files, nstd, &load_error)) {
        return "the standard library";
    }
    run->ids = MS_NEW_N(&run->arena, MsModId, graph->count);
    ms_graph_add_modules(&run->check, &run->names, &run->arena, graph, run->ids);
    for (uint32_t i = 0; i < graph->count; i++) {
        const char *const unported = check_unported(&run->check, &graph->modules[i].syntax);
        if (unported != NULL) {
            return unported;
        }
    }
    return NULL;
}

/* The path the terminal prints for a file: its logical name under the source root. */
static const char *check_shown_file(MsCheckRun *run, const char *name) {
    return run->graph.source_root == NULL || ms_path_is_abs(name) ? name : MS_PATH_JOIN(&run->arena, run->graph.source_root, name);
}

static const char *check_shown(MsCheckRun *run, uint32_t module) {
    return check_shown_file(run, run->graph.modules[module].name);
}

static void check_add_report(MsCheckRun *run, uint32_t module, const MsCheckDiag *diag) {
    run->reports[run->nreports++] = (MsReport){.diag = diag->diag,
                                               .file = run->graph.modules[module].name,
                                               .shown = check_shown(run, module),
                                               .phase = check_phase_name(diag->phase)};
}

/* Runs the passes over every module and gathers their diagnostics, the entry check last. NULL, or what the C
 * passes cannot answer. */
const char *ms_check_diagnose(MsCheckRun *run) {
    const MsGraph *graph = &run->graph;
    if (run->load_failed) {
        run->reports = MS_NEW_N(&run->arena, MsReport, graph->ndiagnostics + 1);
        for (uint32_t i = 0; i < graph->ndiagnostics; i++) {
            const MsGraphDiag *d = &graph->diagnostics[i];
            run->reports[run->nreports++] = (MsReport){.diag = d->diag,
                                                       .file = d->file,
                                                       .shown = check_shown_file(run, d->file),
                                                       .phase = d->phase == MS_GRAPH_PARSE ? "parse" : "resolution"};
        }
        return NULL;
    }
    MsCheck *check = &run->check;
    bool *unchecked = MS_NEW_N(&run->arena, bool, graph->count);
    if (ms_graph_check(check, graph, run->ids, unchecked) != 0) {
        return "a module the passes left unchecked";
    }
    /* What a build owes its fetched packages: natives outside a member and effects a package lacks. */
    MsGraphDiag *package_diags = NULL;
    uint32_t npackage_diags = 0;
    bool complete = true;
    if (graph->package_count != 0 && !ms_graph_check_packages(check, &run->arena, graph, run->ids, &package_diags, &npackage_diags, &complete)) {
        return "the package rules";
    }
    if (!complete) {
        return "a package effect the scan cannot follow";
    }
    size_t total = npackage_diags;
    for (uint32_t i = 0; i < graph->count; i++) {
        ms_module_check_ownership(check, run->ids[i]);
        ms_module_check_unused(check, run->ids[i]);
        if (!check_module_covered(check, run->ids[i])) {
            return "a function or declaration no C pass covers";
        }
        total += check->mods[run->ids[i]].ndiags;
    }
    run->reports = MS_NEW_N(&run->arena, MsReport, total + 1);
    for (uint32_t i = 0; i < graph->count; i++) {
        const MsModuleRow *row = &check->mods[run->ids[i]];
        for (uint32_t k = 0; k < row->ndiags; k++) {
            check_add_report(run, i, &row->diags[k]);
        }
    }
    for (uint32_t i = 0; i < npackage_diags; i++) {
        run->reports[run->nreports++] = (MsReport){.diag = package_diags[i].diag,
                                                   .file = package_diags[i].file,
                                                   .shown = check_shown_file(run, package_diags[i].file),
                                                   .phase = "type"};
    }
    /* The entry module, when it has no diagnostic, must declare a `main` the runtime can start. */
    const uint32_t entry = graph->count - 1;
    MsCheckDiag entry_diag;
    if (check->mods[run->ids[entry]].ndiags == 0 && ms_check_entry(check, run->ids[entry], true, &entry_diag)) {
        check_add_report(run, entry, &entry_diag);
    }
    return NULL;
}

static bool check_in_position_order(const MsReport *reports, size_t count) {
    for (size_t i = 1; i < count; i++) {
        const MsPos a = reports[i - 1].diag.pos, b = reports[i].diag.pos;
        const int files = strcmp(reports[i - 1].file, reports[i].file);
        if (files > 0 || (files == 0 && (a.line > b.line || (a.line == b.line && a.column > b.column)))) {
            return false;
        }
    }
    return true;
}

/* Whether the C answer for these diagnostics equals the Rust one. NULL, or why not. */
static const char *check_renderable(const MsCheckRun *run, bool json) {
    /* JSON diagnostics carry the machine-applicable `fix` the C passes do not all build yet. */
    if (json && run->nreports != 0) {
        return "a diagnostic in the JSON document (its fix is not built in C yet)";
    }
    /* The terminal report names project modules in `add: import` suggestions the C hints do not read. */
    for (size_t i = 0; i < run->nreports; i++) {
        if (check_contains(run->reports[i].diag.message, "; add: import ")) {
            return "an import suggestion that reads the project's modules";
        }
    }
    /* ms_render_text lists diagnostics in position order; the Rust command keeps the checker's order unless every
     * diagnostic is a syntax error, which it sorts. They agree then, and otherwise when the checker's order already
     * is position order. */
    bool all_parse = true;
    for (size_t i = 0; i < run->nreports; i++) {
        all_parse = all_parse && strcmp(run->reports[i].phase, "parse") == 0;
    }
    return all_parse || check_in_position_order(run->reports, run->nreports) ? NULL : "diagnostics not in position order";
}

static int check_print(const MsCheckRun *run, const char *target, bool json, MsBuf *out, MsBuf *err) {
    if (run->nreports != 0) {
        if (json) {
            ms_render_json(out, run->reports, run->nreports);
        } else {
            ms_render_text(err, run->reports, run->nreports);
        }
        return 1;
    }
    if (json) {
        ms_buf_puts(out, "{\n  \"format\": 1,\n  \"diagnostics\": []\n}\n");
    } else if (run->graph.project_root != NULL) {
        ms_buf_printf(out, "Checked %s (%u %s)\n", target, run->graph.count, run->graph.count == 1 ? "module" : "modules");
    } else {
        ms_buf_printf(out, "Checked %s\n", target);
    }
    return 0;
}

void ms_check_run_free(MsCheckRun *run) {
    if (run->have_check) {
        ms_check_free(&run->check);
    }
    ms_arena_free(&run->std_syntax);
    ms_arena_free(&run->arena);
    ms_names_free(&run->names);
}

int ms_check_run(const MsStdFile *std_files, uint32_t nstd, const char *target, bool json, MsBuf *out, MsBuf *err,
                 const char **handover_reason) {
    MsCheckRun run = {0};
    ms_names_init(&run.names);
    int status = MS_CHECK_HANDOVER;
    const char *why = ms_check_load(&run, std_files, nstd, target);
    why = why != NULL ? why : ms_check_diagnose(&run);
    why = why != NULL ? why : check_renderable(&run, json);
    if (why == NULL) {
        status = check_print(&run, target, json, out, err);
    } else if (handover_reason != NULL) {
        *handover_reason = why;
    }
    ms_check_run_free(&run);
    return status;
}
