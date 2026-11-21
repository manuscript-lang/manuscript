/* `ms_tool_check` (include/ms/tool.h): `ms check FILE.ms... [--json [--with-text [--each]]]` for the Manuscript
 * front. A separate archive member from tool.c: it needs the embedded standard library (3 MB), which only programs that
 * call it should carry. */
#include <stdbool.h>
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

static void set_message(ms_str *message_out, const char *text) {
    ms_string_new((const uint8_t *)text, strlen(text), message_out);
}

/* The targets as C strings in one allocation the caller frees (`*paths_out`, with the texts after the pointers), or
 * NULL when memory ran out or a path holds a NUL byte. */
static const char *const *copy_targets(const ms_list *targets, size_t count) {
    size_t bytes = 0;
    for (size_t i = 0; i < count; i++) {
        ms_value value = ms_list_get(targets, i);
        bytes += value.as.buf.len + 1;
        ms_value_free(&value);
    }
    char **paths = malloc(count * sizeof *paths + bytes + 1); /* not the runtime's allocator: this archive's free() is mimalloc's */
    if (paths == NULL) {
        return NULL;
    }
    char *text = (char *)(paths + count);
    bool whole = true;
    for (size_t i = 0; i < count; i++) {
        ms_value value = ms_list_get(targets, i);
        const size_t length = value.as.buf.len;
        memcpy(text, value.as.buf.data, length);
        text[length] = '\0';
        whole = whole && strlen(text) == length;
        paths[i] = text;
        text += length + 1;
        ms_value_free(&value);
    }
    if (!whole) {
        free(paths);
        return NULL;
    }
    return (const char *const *)paths;
}

uint8_t ms_tool_check(const ms_list *targets, uint8_t json, uint8_t with_text, uint8_t each, ms_list *out, ms_str *message_out) {
    const size_t count = ms_list_len(targets);
    const char *const *paths = copy_targets(targets, count);
    if (paths == NULL || count == 0 || (count != 1 && each == 0)) {
        free((void *)paths);
        set_message(message_out, paths == NULL ? "a path that holds a NUL byte" : "one target, or several with --each");
        return 1;
    }
    uint32_t nstd = 0;
    const MsStdFile *std_files = ms_std_embedded(&nstd);
    MsBuf stdout_text = {0}, stderr_text = {0};
    const char *reason = "not covered by the C checker";
    const MsCheckFormat format = {.json = json != 0, .with_text = with_text != 0};
    const int status = each != 0 ? ms_check_run_each(std_files, nstd, paths, count, &stdout_text, &reason)
                                 : ms_check_run(std_files, nstd, paths[0], format, &stdout_text, &stderr_text, &reason);
    free((void *)paths);
    uint8_t result = 0;
    if (status == MS_CHECK_HANDOVER) {
        set_message(message_out, reason);
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
