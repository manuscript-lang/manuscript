/* `ms_tool_facts` (include/ms/tool.h): the fact model of one document for `ms diagram`, `ms inspect` and the review
 * views. A separate archive member from tool.c: it needs the embedded standard library (3 MB), which only programs that
 * call it should carry. */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/dump.h"
#include "ms/ownership.h"
#include "ms/parse.h"
#include "ms/program.h"
#include "ms/std_embed.h"
#include "ms/stdlib.h"
#include "ms/tool.h"

static void put_message(ms_str *message_out, const char *text, size_t length) {
    ms_string_new((const uint8_t *)text, length, message_out);
}

/* Checks `text` (a document whose imports are all standard) as the module `main.ms` and prints its facts. */
static uint8_t facts_of(const ms_str *text, ms_str *out, ms_str *message_out) {
    const char *src = (const char *)ms_str_data(text);
    const size_t len = ms_str_len(text);
    if (!ms_utf8_valid(src, len)) {
        put_message(message_out, "invalid UTF-8", 13);
        return 1;
    }
    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsModule module;
    MsDiag diag;
    uint8_t status = 0;
    MsCheck check;
    ms_check_init(&check, &names);
    uint32_t nfiles = 0;
    const MsStdFile *files = ms_std_embedded(&nfiles);
    MsStr err = {0};
    if (!ms_parse(&syntax, &names, src, len, &module, &diag)) {
        put_message(message_out, diag.message.ptr, diag.message.len);
        status = 1;
    } else if (!ms_module_only_std_imports(&module)) {
        put_message(message_out, "imports a project module", 24);
        status = 2;
    } else if (!ms_std_load(&check, &syntax, files, nfiles, &err)) {
        put_message(message_out, err.ptr, err.len);
        status = 1;
    } else {
        const MsModId id = ms_module_add(&check, ms_intern_cstr(&names, "main.ms"), &module);
        ms_program_begin(&check);
        (void)ms_program_check_module(&check, id, (MsStr){src, (uint32_t)len});
        ms_module_check_ownership(&check, id); /* marks the bindings that close at scope end */
        MsBuf json = {0};
        ms_dump_module_facts(&json, &check, id, (MsStr){src, (uint32_t)len});
        ms_string_new((const uint8_t *)json.data, json.len, out);
        ms_buf_free(&json);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    return status;
}

uint8_t ms_tool_facts(const ms_str *text, ms_str *out, ms_str *message_out) {
    return facts_of(text, out, message_out);
}
