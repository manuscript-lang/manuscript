/* `ms_tool_check` (include/ms/tool.h): `ms check FILE.ms [--json]` for the Manuscript front. A separate archive member
 * from tool.c: it needs the embedded standard library (3 MB), which only programs that call it should carry. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check_run.h"
#include "ms/std_embed.h"
#include "ms/tool.h"

static void push_text(ms_list *out, const char *text, size_t length) {
    ms_value value;
    memset(&value, 0, sizeof value);
    value.kind = MS_STRING;
    value.as.buf.data = (const uint8_t *)text;
    value.as.buf.len = length;
    ms_list_push(out, &value);
}

uint8_t ms_tool_check(const ms_str *target, uint8_t json, ms_list *out, ms_str *message_out) {
    const size_t length = ms_str_len(target);
    char *path = malloc(length + 1); /* not ms_str_cstring: this archive's free() is mimalloc's, the runtime's is not */
    if (path != NULL) {
        memcpy(path, ms_str_data(target), length);
        path[length] = '\0';
    }
    if (path == NULL || strlen(path) != length) {
        free(path);
        static const char text[] = "the path holds a NUL byte";
        ms_string_new((const uint8_t *)text, sizeof text - 1, message_out);
        return 1;
    }
    uint32_t nstd = 0;
    const MsStdFile *std_files = ms_std_embedded(&nstd);
    MsBuf stdout_text = {0}, stderr_text = {0};
    const int status = ms_check_run(std_files, nstd, path, json != 0, &stdout_text, &stderr_text, NULL);
    free(path);
    uint8_t result = 0;
    if (status == MS_CHECK_HANDOVER) {
        static const char text[] = "not covered by the C checker";
        ms_string_new((const uint8_t *)text, sizeof text - 1, message_out);
        result = 2;
    } else {
        char code[16];
        const int n = snprintf(code, sizeof code, "%d", status);
        push_text(out, stdout_text.data == NULL ? "" : (const char *)stdout_text.data, stdout_text.len);
        push_text(out, stderr_text.data == NULL ? "" : (const char *)stderr_text.data, stderr_text.len);
        push_text(out, code, (size_t)n);
    }
    ms_buf_free(&stdout_text);
    ms_buf_free(&stderr_text);
    return result;
}
