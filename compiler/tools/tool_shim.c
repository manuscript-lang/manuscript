/* Bridge from Manuscript `extern fn` declarations to libms. This file includes only `ms_abi.h` (through
 * tool_shim.h) because that header's names collide with libms's; libms's entry points are declared here
 * by hand. */
#include "tool_shim.h"

#include <stdlib.h>

void mi_free(void *block); /* libms allocates with mimalloc (compiler/include/ms_mimalloc.h); the dump is freed the same way */
char *ms_syntax_dump_text(const char *path, const char *text, size_t length, size_t *out_length);

#define MS_TOOL_UNNAMED_SOURCE "<source>"

void ms_tool_syntax_dump(const ms_str *path, const ms_str *text, ms_str *out) {
    char *const path_text = ms_str_cstring(path); /* system malloc, freed with free(); NULL when the path holds a NUL byte */
    size_t dump_length = 0;
    char *const dump = ms_syntax_dump_text(path_text != NULL ? path_text : MS_TOOL_UNNAMED_SOURCE,
                                           (const char *)ms_str_data(text), ms_str_len(text),
                                           &dump_length); /* owned; NULL when the text is not UTF-8 */
    free(path_text);
    if (dump == NULL) {
        return;
    }
    ms_string_new((const uint8_t *)dump, dump_length, out);
    mi_free(dump);
}
