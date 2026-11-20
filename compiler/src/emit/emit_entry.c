/* The program entry both emitters share: the module's entry function is renamed `ms_entry`, and a C
 * `main(argc, argv)` hands it to the runtime (`msrt_start`), which runs it on a task stack. A test
 * that links its own runtime (compiler/tests/backend_rt.c) skips both and calls the entry itself. */
#include <string.h>

#include "ms/emit_entry.h"

/* The symbol of the entry function once renamed; the user's `main` cannot keep its own name, which
 * the C entry point takes. */
#define MIR_ENTRY_SYMBOL "ms_entry"

void mir_name_entry(MirModule *m) {
    if (m->entry != MIR_NONE) {
        m->funcs[m->entry].name = mir_name(m, MIR_ENTRY_SYMBOL, strlen(MIR_ENTRY_SYMBOL));
    }
}

void mir_emit_entry_main(const MirModule *m, bool llvm, bool tables, MsBuf *out) {
    if (m->entry == MIR_NONE) {
        return;
    }
    /* Without `tables` the argument is null and the runtime has no function or line names for traces;
     * with them it is `ms_tables`, the block ms_asm_tables appends to the assembly (QBE only so far). */
    if (llvm) {
        ms_buf_puts(out,
                    "declare i32 @msrt_start(ptr, ptr, i32, ptr)\n\n"
                    "define i32 @main(i32 %argc, ptr %argv) {\n"
                    "  %r = call i32 @msrt_start(ptr @\"" MIR_ENTRY_SYMBOL "\", ptr null, i32 %argc, ptr %argv)\n"
                    "  ret i32 %r\n}\n");
        return;
    }
    ms_buf_printf(out,
                  "export function w $main(w %%argc, l %%argv) {\n@start\n"
                  "\t%%r =w call $msrt_start(l $" MIR_ENTRY_SYMBOL ", l %s, w %%argc, l %%argv)\n"
                  "\tret %%r\n}\n",
                  tables ? "$ms_tables" : "0");
}
