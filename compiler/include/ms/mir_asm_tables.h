/* Fault tables from the assembly a backend wrote, with no debug-info reader. The emitter writes a
 * source place (`.loc 1 <line> <scope>`) before each instruction (QBE: `dbgloc`), and a small text
 * description of the module's functions and inlined scopes (the "meta"); `mir_asm_tables` puts a
 * label after every `.loc` and at the end of every function, and appends the tables as data whose
 * addresses are those labels, so the assembler and linker fill them in. The symbol `ms_tables` names
 * the block `msrt_start` takes. */
#ifndef MS_MIR_ASM_TABLES_H
#define MS_MIR_ASM_TABLES_H

#include "ms/mir.h"

/* The meta of `m` for the QBE backend, appended to `out`: `F <path>` per file, `Y <symbol> <file> <line>
 * <name>` per function and `S <file> <parent> <call line> <name>` per inlined scope (tab separated;
 * file -1 when unknown; scopes numbered module wide, as the `dbgloc` lines are). */
void mir_qbe_tables_meta(const MirModule *m, MsBuf *out);

/* Writes `asm_text` with the labels added, followed by the tables, to `out`. `prefix` is what the
 * target puts before a symbol ("_" on Apple, else ""). Returns false with a reason in `why`. */
bool mir_asm_tables(const char *meta, size_t meta_len, const char *asm_text, size_t asm_len,
                    const char *prefix, MsBuf *out, MsBuf *why);

#endif
