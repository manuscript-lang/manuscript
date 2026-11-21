/* Checking a loaded graph (project.h): the module graph the loader built, handed to the checker through
 * MsModuleRow.import_targets and the program's method table (program.h). */
#include "ms/effects.h"
#include "ms/program.h"
#include "ms/project.h"

void ms_graph_add_modules(MsCheck *c, MsNames *names, MsArena *a, const MsGraph *graph, MsModId *ids) {
    for (uint32_t i = 0; i < graph->count; i++) {
        const MsGraphModule *module = &graph->modules[i];
        const MsModId id = ms_module_add(c, ms_intern_cstr(names, module->name), &module->syntax);
        MsModId *targets = MS_NEW_N(a, MsModId, module->syntax.nimports + 1);
        for (uint32_t k = 0; k < module->syntax.nimports; k++) {
            /* Imports come before the module in the graph, so their ids are known. */
            targets[k] = module->targets[k] < 0 ? MS_NONE : ids[module->targets[k]];
        }
        c->mods[id].import_targets = targets;
        ids[i] = id;
    }
}

uint32_t ms_graph_check(MsCheck *c, const MsGraph *graph, const MsModId *ids, bool *unchecked) {
    uint32_t skipped = 0;
    ms_program_begin(c);
    for (uint32_t i = 0; i < graph->count; i++) {
        const MsGraphModule *module = &graph->modules[i];
        const bool checked = ms_program_check_module(c, ids[i], (MsStr){module->source, (uint32_t)module->length});
        if (unchecked != NULL) {
            unchecked[i] = !checked;
        }
        skipped += !checked;
    }
    return skipped;
}

/* ---- fetched packages ---- */

/* The package whose prefix starts the module's logical name, or NULL for the project's own module. */
static const MsGraphPackage *graph_package_of(const MsGraph *graph, const char *name) {
    const MsGraphPackage *best = NULL;
    for (uint32_t i = 0; i < graph->package_count; i++) {
        const size_t length = strlen(graph->packages[i].prefix);
        if (strncmp(name, graph->packages[i].prefix, length) == 0 && (best == NULL || length > strlen(best->prefix))) {
            best = &graph->packages[i];
        }
    }
    return best;
}

/* The package name diagnostics use: its prefix without the trailing `/`. */
static const char *graph_package_name(MsArena *a, const MsGraphPackage *package) {
    return ms_arena_strndup(a, package->prefix, strlen(package->prefix) - 1);
}

static void graph_diag(MsBuf *out, const char *file, MsPos pos, const char *message) {
    MsGraphDiag d = {.file = file, .phase = MS_GRAPH_TYPE};
    d.diag.pos = pos;
    d.diag.message = (MsStr){message, (uint32_t)strlen(message)};
    MS_VEC_PUSH(*out, MsGraphDiag, d);
}

/* A package holds Manuscript source only: its native declarations are errors. */
static void graph_reject_natives(MsArena *a, MsNames *names, MsBuf *out, const MsGraphModule *module, const char *package) {
    for (uint32_t i = 0; i < module->syntax.ndecls; i++) {
        const MsDecl *d = module->syntax.decls[i];
        const bool external = (d->kind == MS_D_FN && d->u.fn.external) || (d->kind == MS_D_TYPE && d->u.type.external);
        if (external) {
            const MsStr name = ms_name(names, d->kind == MS_D_FN ? d->u.fn.name : d->u.type.name);
            graph_diag(out, module->name, d->pos, ms_arena_fmt(a, "package %s declares native `%.*s`; packages hold Manuscript source only, so call the standard library instead", package, (int)name.len, name.ptr).ptr);
        }
    }
}

bool ms_graph_check_packages(MsCheck *c, MsArena *a, const MsGraph *graph, const MsModId *ids, MsGraphDiag **out, uint32_t *count, bool *complete) {
    MsBuf found = {0};
    MsEffectModule *modules = MS_NEW_N(a, MsEffectModule, (size_t)graph->count + 1);
    for (uint32_t i = 0; i < graph->count; i++) {
        const MsGraphModule *module = &graph->modules[i];
        const MsGraphPackage *package = graph_package_of(graph, module->name);
        modules[i] = (MsEffectModule){.id = ids[i], .text = {module->source, (uint32_t)module->length}};
        if (package != NULL) {
            MsStr *names = MS_NEW_N(a, MsStr, (size_t)package->effect_count + 1);
            for (uint32_t k = 0; k < package->effect_count; k++) {
                names[k] = (MsStr){package->effects[k], (uint32_t)strlen(package->effects[k])};
            }
            modules[i].cap = (MsEffectScope){.names = names, .count = package->effect_count, .present = true};
            modules[i].package = graph_package_name(a, package);
            if (!package->member) {
                graph_reject_natives(a, c->names, &found, module, modules[i].package);
            }
        }
    }
    MsPackageViolation *violations;
    uint32_t nviolations;
    const bool ok = ms_effect_package_violations(a, c, modules, graph->count, &violations, &nviolations, complete);
    for (uint32_t i = 0; ok && i < nviolations; i++) {
        graph_diag(&found, violations[i].file, violations[i].pos, violations[i].message);
    }
    const uint32_t total = (uint32_t)MS_VEC_LEN(found, MsGraphDiag);
    *out = MS_NEW_N(a, MsGraphDiag, (size_t)total + 1);
    if (total > 0) {
        memcpy(*out, found.data, total * sizeof(MsGraphDiag));
    }
    *count = total;
    ms_buf_free(&found);
    return ok;
}
