/* The state of one `ms check` / `ms build` run over a loaded project (check_cmd.c), shared by the commands that go on to
 * lower the checked program (build_cmd.c). */
#ifndef MS_CHECK_RUN_STATE_H
#define MS_CHECK_RUN_STATE_H

#include "ms/check.h"
#include "ms/diag_render.h"
#include "ms/project.h"
#include "ms/stdlib.h"

typedef struct MsCheckRun {
    MsNames names;
    MsArena arena, std_syntax;
    MsGraph graph;
    MsCheck check;
    bool have_check;
    MsModId *ids;
    MsReport *reports;
    size_t nreports;
    bool load_failed; /* the graph holds the diagnostics of the load, and nothing was checked */
} MsCheckRun;

/* Loads the graph and the standard library and declares the modules. NULL, or what the C passes cannot answer. */
const char *ms_check_load(MsCheckRun *run, const MsStdFile *std_files, uint32_t nstd, const char *target);
/* Runs the passes over every module and gathers their diagnostics into `run->reports`. NULL, or what they cannot answer. */
const char *ms_check_diagnose(MsCheckRun *run);
/* Frees everything the run holds. */
void ms_check_run_free(MsCheckRun *run);

#endif
