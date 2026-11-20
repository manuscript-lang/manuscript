/* Fault tables from the assembly a backend wrote, with no debug-info reader. The emitter writes a
 * source place (`.loc 1 <line> <scope>`) before each instruction, and a small text
 * description of the module's functions and inlined scopes (the "meta"); `mir_asm_tables` puts a
 * label after every `.loc` and at the end of every function, and appends the tables as data whose
 * addresses are those labels, so the assembler and linker fill them in. The symbol `ms_tables` names
 * the block `msrt_start` takes. */
#ifndef MS_MIR_ASM_TABLES_H
#define MS_MIR_ASM_TABLES_H

#include "ms/mir.h"

/* The meta of `m` for the LLVM backend, appended to `out`: `F <path>` per file, `Y <symbol> <file> <line>
 * <name>` per function and `S <file> <parent> <call line> <name>` per inlined scope (tab separated;
 * file -1 when unknown; scopes numbered module wide, as the `dbgloc` lines are). */
/* `display` is each function's source name, before `mir_name_symbols` made the symbols unique. */
void mir_tables_meta(const MirModule *m, const MsSym *display, uint32_t ndisplay, MsBuf *out);

/* Writes `asm_text` with the labels added, followed by the tables, to `out`. `prefix` is what the
 * target puts before a symbol ("_" on Apple, else ""); `strip_lines` leaves the `.loc` directives out of the
 * output (the labels stay). A function of the meta that has no code in the assembly (LLVM removed it) gets no
 * table entry. Always succeeds; `why` is kept for a future reason. */
bool mir_asm_tables(const char *meta, size_t meta_len, const char *asm_text, size_t asm_len,
                    const char *prefix, bool strip_lines, MsBuf *out, MsBuf *why);

#endif
