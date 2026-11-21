/* `ms build FILE.ms` in C (ms_build_program; the Manuscript front calls it through ms_tool_build). The program is
 * loaded and checked as `ms check` does (check_cmd.c), lowered whole (ms_lower_program), finished by the MIR
 * pipeline, compiled to an object (build/object.c) and linked with the runtime (build/link.c). Anything the C
 * passes do not decide goes to the Rust `ms`: every diagnostic, and a program whose entry the lowering did not
 * produce. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/build_link.h"
#include "ms/build_object.h"
#include "ms/build_run.h"
#include "ms/check_run_state.h"
#include "ms/build_tool.h"
#include "ms_rt/sys_fs.h"
#include "ms/lower.h"
#include "ms/mir_pass.h"
#include "ms/program.h"

/* Whether the lowering produced the process entry, an exported `main`, which it names as the module's entry. */
static bool build_find_entry(MirModule *m) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        const MsStr name = ms_name(&m->names, m->funcs[i].name);
        if (m->funcs[i].linkage == ML_EXPORT && name.len == 4 && memcmp(name.ptr, "main", 4) == 0) {
            m->entry = i;
            return true;
        }
    }
    return false;
}

/* The program's MIR text after the pipeline's first step, or NULL and why. */
static const char *build_mir_text(MsCheckRun *run, MsBuf *text, MsBuf *err) {
    MsCheck *check = &run->check;
    (void)ms_program_check_bundled(check);
    MirModule mir;
    mir_module_init(&mir);
    const MsModId entry = run->ids[run->graph.count - 1];
    (void)ms_lower_program(check, entry, &mir);
    const char *why = NULL;
    if (!build_find_entry(&mir)) {
        why = "a program the C lowering does not cover";
    } else {
        const MirPipelineOptions options = {.checks = true, .verify = true};
        if (!mir_pipeline_prepare(&mir, &options, err)) {
            why = "the MIR pipeline refused the program";
        } else {
            mir_print_module(&mir, text);
        }
    }
    mir_module_free(&mir);
    return why;
}

/* `<output>.ms-build.json`: what built the executable, as the Rust command writes it. */
static bool build_write_metadata(const MsBuildRequest *request) {
    char path[4096], staged[4096];
    if (snprintf(path, sizeof path, "%s.ms-build.json", request->output) >= (int)sizeof path ||
        snprintf(staged, sizeof staged, "%s.part", path) >= (int)sizeof staged) {
        return false;
    }
    MsBuf text = {0};
    ms_buf_printf(&text, "{\n  \"format\": 1,\n  \"version\": \"%s\",\n  \"backend\": \"llvm\",\n  \"build_type\": \"%s\"\n}\n",
                  request->version, request->release ? "Release" : "Debug");
    const bool ok = ms_build_write(staged, text.data, text.len) && ms_sys_fs_rename(staged, path) == 0;
    ms_buf_free(&text);
    return ok;
}

/* Writes the object, links it with the runtime to `<output>.part` and moves that over `output`. */
static int build_link(const MsBuildRequest *request, const MsBackendText *object, MsBuf *err) {
    char object_path[4096], staged[4096], llc[4096];
    if (snprintf(object_path, sizeof object_path, "%s.o", request->output) >= (int)sizeof object_path ||
        snprintf(staged, sizeof staged, "%s.part", request->output) >= (int)sizeof staged ||
        snprintf(llc, sizeof llc, "%s/llc", request->tools) >= (int)sizeof llc) {
        ms_buf_puts(err, "the output path is too long");
        return 1;
    }
    if (!ms_build_write(object_path, object->ptr, object->len)) {
        ms_buf_printf(err, "cannot write %s", object_path);
        return 1;
    }
    const MsLinkOptions options = {.lld = request->lld, .llc = llc, .files = request->files};
    const char *const inputs[] = {request->runtime};
    MsBackendText why = {0};
    int status = 0;
    if (!ms_build_link(object_path, inputs, 1, staged, &options, &why)) {
        ms_buf_printf(err, "%.*s", (int)why.len, why.ptr != NULL ? why.ptr : "link failed");
        ms_backend_free(&why);
        status = 1;
    } else if (ms_sys_fs_rename(staged, request->output) != 0) {
        ms_buf_printf(err, "cannot write %s", request->output);
        status = 1;
    } else if (!build_write_metadata(request)) {
        ms_buf_printf(err, "cannot write build metadata %s.ms-build.json", request->output);
        status = 1;
    }
    ms_build_unlink(object_path);
    ms_build_unlink(staged);
    return status;
}

static int build_object_and_link(const MsBuildRequest *request, const MsBuf *mir, MsBuf *err) {
    MsObjectOptions options = {.tools = request->tools};
    options.backend = (MsBackendOptions){.speed = request->release, .checks = true, .verify = true, .tables = true};
    MsBackendText object = {0}, why = {0};
    if (!ms_build_object((const char *)mir->data, mir->len, "", 0, &options, &object, &why)) {
        ms_buf_printf(err, "native code generation failed: %.*s", (int)why.len, why.ptr != NULL ? why.ptr : "");
        ms_backend_free(&why);
        return 1;
    }
    const int status = build_link(request, &object, err);
    ms_backend_free(&object);
    return status;
}

int ms_build_program(const MsStdFile *std_files, uint32_t nstd, const MsBuildRequest *request, MsBuf *err,
                     const char **handover_reason) {
    MsCheckRun run = {0};
    ms_names_init(&run.names);
    int status = MS_BUILD_HANDOVER;
    const char *why = ms_build_host_ported() ? NULL : "a host the C build does not link for yet, which the Rust command does";
    why = why != NULL ? why : ms_check_load(&run, std_files, nstd, request->target);
    why = why != NULL ? why : ms_check_diagnose(&run);
    if (why == NULL && (run.load_failed || run.nreports != 0)) {
        why = "a diagnostic, which the Rust command renders";
    }
    MsBuf mir = {0};
    why = why != NULL ? why : build_mir_text(&run, &mir, err);
    if (why == NULL) {
        status = build_object_and_link(request, &mir, err);
    } else if (handover_reason != NULL) {
        *handover_reason = why;
    }
    ms_buf_free(&mir);
    ms_check_run_free(&run);
    return status;
}
