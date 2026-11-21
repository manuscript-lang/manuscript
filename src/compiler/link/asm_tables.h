/* compiler/link/asm_tables.h: the fault tables as assembly.
 *
 * The runtime names functions and source lines in a fault trace from a table of code addresses (MsTables). Only
 * the assembler knows those addresses, so after `llc` wrote the program's assembly this step puts a label at the
 * start and end of every function and at every source place (`.loc`), asks MIR for the table bytes
 * (mir_fault_tables), and appends them to the assembly as data whose address words are label differences and
 * symbols the assembler and linker resolve. The result defines the symbol `ms_tables`. */
#ifndef MS_COMPILER_LINK_ASM_TABLES_H
#define MS_COMPILER_LINK_ASM_TABLES_H

#include "compiler/link/asm_scan.h"

/* The assembly format of the host. */
AsmFormat asm_host_format(void);

/* Rewrites `assembly` into `out` and appends the tables. `module` is renamed (emit_name_symbols) and `info`
 * was made before that. A function LLVM removed is left out of the tables. */
bool link_asm_tables(MsArena *arena, const MirModule *module, const EmitTableInfo *info, MsSpan assembly,
                     MsStrBuild *out, MsStrBuild *why);

#endif
