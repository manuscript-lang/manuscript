/* ms_macho_symbols FILE...: prints `D name` for each global symbol a Mach-O object or archive defines and `U name` for each
 * it imports, then `debug` when a file has a `__debug_info` section (ms/build_macho.h). */
#include <stdio.h>
#include <stdlib.h>

#include "ms/build_macho.h"
#include "read_file.h"

int main(int argc, char **argv) {
    MsMachoSymbols symbols = {0};
    for (int i = 1; i < argc; i++) {
        size_t len = 0;
        char *data = read_whole_file(argv[i], &len);
        if (data == NULL) {
            fprintf(stderr, "ms_macho_symbols: cannot read %s\n", argv[i]);
            return 1;
        }
        ms_macho_collect(data, len, &symbols);
        /* The symbols point into the data: print before freeing it. */
        const MsStr *defined = ms_buf_items(&symbols.defined);
        for (size_t k = 0; k < MS_VEC_LEN(symbols.defined, MsStr); k++) {
            printf("D %.*s\n", (int)defined[k].len, defined[k].ptr);
        }
        const MsStr *undefined = ms_buf_items(&symbols.undefined);
        for (size_t k = 0; k < MS_VEC_LEN(symbols.undefined, MsStr); k++) {
            printf("U %.*s\n", (int)undefined[k].len, undefined[k].ptr);
        }
        symbols.defined.len = 0;
        symbols.undefined.len = 0;
        if (symbols.debug) {
            puts("debug");
            symbols.debug = false;
        }
        free(data);
    }
    ms_macho_free(&symbols);
    return 0;
}
