/* Checking a loaded graph (project.h): the module graph the loader built, handed to the checker through
 * MsModuleRow.import_targets and the program's method table (program.h). */
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
