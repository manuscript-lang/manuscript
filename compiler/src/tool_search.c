/* `ms_tool_api_model` (include/ms/tool.h): the standard library's API model for `ms search_symbol`. A separate archive
 * member from tool.c: it needs the embedded standard library (3 MB), which only programs that call it should carry. */
#include <stdlib.h>
#include <string.h>

#include "ms/api_model.h"
#include "ms/check.h"
#include "ms/std_embed.h"
#include "ms/tool.h"

void ms_tool_api_model(ms_str *out) {
    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    uint32_t nfiles = 0;
    const MsStdFile *files = ms_std_embedded(&nfiles);
    MsStr err = {0};
    if (ms_std_load(&check, &syntax, files, nfiles, &err)) {
        MsBuf json = {0};
        ms_api_model_json(&json, &check, files, nfiles);
        ms_string_new((const uint8_t *)json.data, json.len, out);
        ms_buf_free(&json);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
}
