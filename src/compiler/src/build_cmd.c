/* `ms build FILE.ms` in C (ms_build_program; the Manuscript front calls it through ms_tool_build). The program is
 * loaded and checked as `ms check` does (check_cmd.c), lowered whole (ms_lower_program), finished by the MIR
 * pipeline, compiled to an object (build/object.c) and linked with the runtime (build/link.c). Anything the C
 * passes do not decide goes to the Rust `ms`: every diagnostic, and a program whose entry the lowering did not
 * produce. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ms/build_link.h"
#include "ms/build_object.h"
#include "ms/build_run.h"
#include "ms/check_run_state.h"
#include "ms/build_tool.h"
#include "ms/lower.h"
#include "ms/mir_pass.h"
#include "ms/program.h"

static bool build_line_has(const char *line, size_t length, const char *needle) {
    const size_t n = strlen(needle);
    for (size_t i = 0; i + n <= length; i++) {
        if (memcmp(line + i, needle, n) == 0) {
            return true;
        }
    }
    return false;
}

/* The line of the lowering's refusals that names `main` (the program's own place and why), else the first. A test build
 * takes the first line of the test runner instead, which every test needs. */
static void build_refusal(const MsBuf *refused, bool tests, MsBuf *out) {
    size_t start = 0, chosen = 0, chosen_len = 0;
    bool found = false;
    while (start < refused->len) {
        size_t end = start;
        while (end < refused->len && refused->data[end] != '\n') {
            end++;
        }
        const bool is_main = tests ? build_line_has((const char *)refused->data + start, end - start, "test_runner.ms:")
                                   : end - start > 5 && memcmp(refused->data + start, "main\t", 5) == 0;
        if (!found && (is_main || start == 0)) {
            chosen = start;
            chosen_len = end - start;
            found = is_main;
        }
        start = end + 1;
    }
    ms_buf_put(out, refused->data + chosen, chosen_len);
}

/* The program's MIR text after the pipeline's first step, or NULL and why. */
static const char *build_mir_text(MsCheckRun *run, uint8_t tests, MsBuf *text, MsBuf *names, MsBuf *err) {
    MsCheck *check = &run->check;
    if (tests != 0) {
        ms_program_reach_bundled(check, "@std/internal/test_runner.ms");
    }
    (void)ms_program_check_bundled(check);
    MirModule mir;
    mir_module_init(&mir);
    MsBuf refused = {0};
    if (tests != 0) {
        (void)ms_lower_tests_why(check, run->ids, run->graph.count, tests == 2, &mir, names, &refused);
    } else {
        (void)ms_lower_program_why(check, run->ids[run->graph.count - 1], &mir, &refused);
    }
    const char *why = NULL;
    if (mir.entry == MIR_NONE) {
        why = tests != 0 ? "tests the C lowering does not cover" : "a program the C lowering does not cover";
        build_refusal(&refused, tests != 0, err); /* what the census shows beside the reason */
    } else {
        const MirPipelineOptions options = {.checks = true, .verify = true};
        if (!mir_pipeline_prepare(&mir, &options, err)) {
            why = "the MIR pipeline refused the program";
        } else {
            mir_print_module(&mir, text);
        }
    }
    ms_buf_free(&refused);
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
    const bool ok = ms_build_write(staged, text.data, text.len) && rename(staged, path) == 0;
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
    } else if (rename(staged, request->output) != 0) {
        ms_buf_printf(err, "cannot write %s", request->output);
        status = 1;
    } else if (!build_write_metadata(request)) {
        ms_buf_printf(err, "cannot write build metadata %s.ms-build.json", request->output);
        status = 1;
    }
    (void)unlink(object_path);
    (void)unlink(staged);
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

/* `<output>.tests`: the source root, the project root and each test's identity, which `ms test` reads. */
static bool build_write_listing(const MsBuildRequest *request, const MsGraph *graph, const MsBuf *names) {
    char path[4096], staged[4096];
    if (snprintf(path, sizeof path, "%s.tests", request->output) >= (int)sizeof path ||
        snprintf(staged, sizeof staged, "%s.part", path) >= (int)sizeof staged) {
        return false;
    }
    MsBuf text = {0};
    ms_buf_printf(&text, "%s\n%s\n", graph->source_root != NULL ? graph->source_root : "", graph->project_root != NULL ? graph->project_root : "");
    ms_buf_put(&text, names->data, names->len);
    const bool ok = ms_build_write(staged, text.data, text.len) && rename(staged, path) == 0;
    ms_buf_free(&text);
    return ok;
}

/* The lines of `text` as an array, for the loader's extra files; NULL entries end nothing: `count` says how many. */
static const char **build_split_lines(MsArena *a, const char *text, uint32_t *count) {
    *count = 0;
    if (text == NULL || text[0] == 0) {
        return NULL;
    }
    uint32_t lines = 1;
    for (const char *p = text; *p != 0; p++) {
        lines += *p == '\n' ? 1u : 0u;
    }
    const char **out = MS_NEW_N(a, const char *, lines);
    const char *start = text;
    for (const char *p = text;; p++) {
        if (*p == '\n' || *p == 0) {
            if (p > start) {
                out[(*count)++] = ms_arena_strndup(a, start, (size_t)(p - start));
            }
            start = p + 1;
        }
        if (*p == 0) {
            break;
        }
    }
    return out;
}

int ms_build_program(const MsStdFile *std_files, uint32_t nstd, const MsBuildRequest *request, MsBuf *err,
                     const char **handover_reason) {
    MsCheckRun run = {0};
    ms_names_init(&run.names);
    int status = MS_BUILD_HANDOVER;
    MsLoadTests load = {0};
    if (request->tests != 0) {
        load.extra = (const char *const *)build_split_lines(&run.arena, request->extra, &load.count);
        run.tests = &load;
    }
    const char *why = ms_check_load(&run, std_files, nstd, request->target);
    why = why != NULL ? why : ms_check_diagnose(&run);
    if (why == NULL && (run.load_failed || run.nreports != 0)) {
        why = "a diagnostic, which the Rust command renders";
    }
    MsBuf mir = {0}, names = {0};
    why = why != NULL ? why : build_mir_text(&run, request->tests, &mir, &names, err);
    if (why == NULL) {
        status = build_object_and_link(request, &mir, err);
        if (status == 0 && request->tests != 0 && !build_write_listing(request, &run.graph, &names)) {
            ms_buf_printf(err, "cannot write %s.tests", request->output);
            status = 1;
        }
    } else if (handover_reason != NULL) {
        *handover_reason = why;
    }
    ms_buf_free(&mir);
    ms_buf_free(&names);
    ms_check_run_free(&run);
    return status;
}
