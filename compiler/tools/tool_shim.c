/* Entry points Manuscript tools call over libms with `extern fn` (see compiler/README.md). Strings
 * cross as `ms_str`, per crates/ms-rt-abi/include/ms_abi.h. This file includes only that header
 * because its names collide with libms's; libms's own entry points are declared by hand. */
#include <stdlib.h>
#include <string.h>

#include "ms_abi.h"

char *ms_syntax_dump_text(const char *path, const char *text, size_t len, size_t *out_len);

/* ms_syntax_dump_text on strings: the dump, or the empty string when `text` is not UTF-8. */
void ms_tool_syntax_dump(const ms_str *path, const ms_str *text, ms_str *out) {
    char *p = ms_str_cstring(path);
    size_t n = 0;
    char *dump = ms_syntax_dump_text(p ? p : "", (const char *)ms_str_data(text), ms_str_len(text), &n);
    free(p);
    if (dump != NULL) {
        ms_string_new((const uint8_t *)dump, n, out);
        free(dump);
    }
}
