/* The program entry: functions get symbols that cannot clash with each other or
 * with the runtime and libc (a user function may be called `main`, `write` or `cleanup.thunk`), the
 * entry function is renamed `ms_entry`, and a C
 * `main(argc, argv)` hands it to the runtime (`msrt_start`), which runs it on a task stack. A test
 * that links its own runtime (src/compiler/tests/backend_rt.c) skips both and calls the entry itself. */
#include <string.h>

#include "ms/emit_entry.h"

/* The symbol of the entry function once renamed; the user's `main` cannot keep its own name, which
 * the C entry point takes. */
#define MIR_ENTRY_SYMBOL "ms_entry"

void mir_name_symbols(MirModule *m) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        MirFunc *f = &m->funcs[i];
        if (i == m->entry) {
            f->name = mir_name(m, MIR_ENTRY_SYMBOL, strlen(MIR_ENTRY_SYMBOL));
        } else if (f->linkage != ML_EXPORT) {
            const MsStr base = ms_name(&m->names, f->name);
            const MsStr unique = ms_arena_fmt(&m->arena, "%.*s.%u", (int)base.len, base.ptr, i);
            f->name = mir_name(m, unique.ptr, unique.len);
        }
    }
}

void mir_emit_entry_main(const MirModule *m, bool tables, MsBuf *out) {
    if (m->entry == MIR_NONE) {
        return;
    }
    /* Without `tables` the argument is null and the runtime has no function or line names for traces;
     * with them it is `ms_tables`, the block ms_asm_tables appends to the assembly. */
    ms_buf_printf(out,
                  "%sdeclare i32 @msrt_start(ptr, ptr, i32, ptr)\n\n"
                  "define i32 @main(i32 %%argc, ptr %%argv) {\n"
                  "  %%r = call i32 @msrt_start(ptr @\"" MIR_ENTRY_SYMBOL "\", ptr %s, i32 %%argc, ptr %%argv)\n"
                  "  ret i32 %%r\n}\n",
                  tables ? "@ms_tables = external global i8\n" : "", tables ? "@ms_tables" : "null");
}
