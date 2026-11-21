/* compiler/link/macho.h: the global symbols of 64-bit little-endian Mach-O object files and of the archives
 * of them, which the macOS link needs to write SDK stubs. Anything else it does not recognize is skipped. */
#ifndef MS_COMPILER_LINK_MACHO_H
#define MS_COMPILER_LINK_MACHO_H

#include "base/intern.h"

typedef struct MachoSymbols {
  MsSpanList defined;   /* owned list of spans into the file data: global symbols the files define */
  MsSpanList undefined; /* owned list of spans into the file data: global symbols they import */
  bool debug;           /* a file carries a `__debug_info` section */
} MachoSymbols;

/* Adds the symbols of one object file or archive; `data` must outlive `out`. */
void macho_collect(MsSpan data, MachoSymbols *out);
void macho_free(MachoSymbols *symbols);

#endif
