/* `ms_tool_build` (include/ms/tool.h): `ms build FILE.ms` for the Manuscript front. A separate archive member from
 * tool.c for the same reason as tool_check.c: it carries the embedded standard library. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/build_run.h"
#include "ms/std_embed.h"
#include "ms/tool.h"

#ifndef MS_VERSION
#define MS_VERSION "0"
#endif

/* A NUL-terminated copy of `text`, or NULL when it holds a NUL byte (not ms_str_cstring: this archive's free() is
 * mimalloc's, the runtime's is not). */
static char *copy_path(const ms_str *text) {
    const size_t length = ms_str_len(text);
    char *path = malloc(length + 1);
    if (path == NULL) {
        return NULL;
    }
    memcpy(path, ms_str_data(text), length);
    path[length] = '\0';
    if (strlen(path) != length) {
        free(path);
        return NULL;
    }
    return path;
}

uint8_t ms_tool_build(const ms_str *target, const ms_str *output, const ms_str *runtime, const ms_str *tools,
                      const ms_str *lld, const ms_str *files, uint8_t release, ms_list *out, ms_str *message_out) {
    (void)out; /* nothing to return: the executable is the result */
    char *paths[6] = {copy_path(target), copy_path(output), copy_path(runtime), copy_path(tools), copy_path(lld), copy_path(files)};
    bool complete = true;
    for (size_t i = 0; i < 6; i++) {
        complete = complete && paths[i] != NULL;
    }
    uint8_t result = 1;
    const char *text = "a path is missing or holds a NUL byte";
    size_t length = strlen(text);
    MsBuf err = {0};
    if (complete) {
        const MsBuildRequest request = {.target = paths[0], .output = paths[1], .runtime = paths[2], .tools = paths[3],
                                        .lld = paths[4], .files = paths[5], .release = release != 0, .version = MS_VERSION};
        uint32_t nstd = 0;
        const MsStdFile *std_files = ms_std_embedded(&nstd);
        const char *reason = "not covered by the C build";
        const int status = ms_build_program(std_files, nstd, &request, &err, &reason);
        if (status == MS_BUILD_HANDOVER) {
            result = 2;
            text = reason;
            length = strlen(reason);
            if (err.len != 0) { /* the lowering's first refusal rides with the reason */
                MsBuf detail = {0};
                ms_buf_printf(&detail, "%s: %.*s", reason, (int)err.len, (const char *)err.data);
                ms_buf_free(&err);
                err = detail;
                text = (const char *)err.data;
                length = err.len;
            }
        } else if (status == 0) {
            result = 0;
        } else {
            text = err.data == NULL ? "build failed" : (const char *)err.data;
            length = err.data == NULL ? strlen(text) : err.len;
        }
    }
    if (result != 0) {
        ms_string_new((const uint8_t *)text, length, message_out);
    }
    ms_buf_free(&err);
    for (size_t i = 0; i < 6; i++) {
        free(paths[i]);
    }
    return result;
}
