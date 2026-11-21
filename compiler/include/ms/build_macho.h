/* The global symbols of Mach-O object files and of the archives of them (the macOS link needs them to write SDK
 * stubs). Reads 64-bit little-endian Mach-O only; anything else it does not recognize is skipped. */
#ifndef MS_BUILD_MACHO_H
#define MS_BUILD_MACHO_H

#include <stdbool.h>
#include <stddef.h>

#include "ms/base.h"

typedef struct MsMachoSymbols {
    MsBuf defined;   /* MsStr: global symbols the files define; slices of the file data */
    MsBuf undefined; /* MsStr: global symbols they import */
    bool debug;      /* a file carries a `__debug_info` section */
} MsMachoSymbols;

/* Adds the symbols of one object file or archive (`data`, `len`), which must outlive `out`. */
void ms_macho_collect(const char *data, size_t len, MsMachoSymbols *out);
void ms_macho_free(MsMachoSymbols *symbols);

#endif
