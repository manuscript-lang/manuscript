/* Owns symbol names and the program's C `main`. */
#include "compiler/emit/emit.h"

#include "compiler/emit/emit_cx.h"

void emit_name_symbols(MirModule *module) {
  MsStrBuild text = ms_strbuild_new();
  for (uint32_t index = 0; index < module->funcs.len; index++) {
    MirFunc *func = &module->funcs.ptr[index];
    if (func->display == MS_NAME_EMPTY) {
      func->display = func->name; /* the source name survives for the debugger */
    }
    if (index == module->entry) {
      func->name = mir_name(module, ms_span_of_text(EMIT_ENTRY_SYMBOL));
    } else if (func->linkage != ML_EXPORT) {
      ms_strbuild_clear(&text);
      ms_strbuild_append(&text, ms_names_span(&module->names, func->name));
      ms_strbuild_printf(&text, ".%u", index);
      func->name = mir_name(module, ms_strbuild_span(&text));
    }
  }
  ms_strbuild_free(&text);
}

void emit_entry_main(const MirModule *module, bool tables, MsStrBuild *out) {
  if (module->entry == MIR_NONE) {
    return;
  }
  ms_strbuild_printf(out,
                     "%sdeclare i32 @msrt_start(ptr, ptr, i32, ptr)\n\n"
                     "define i32 @main(i32 %%argc, ptr %%argv) {\n"
                     "  %%r = call i32 @msrt_start(ptr @\"" EMIT_ENTRY_SYMBOL "\", ptr %s, i32 %%argc, ptr %%argv)\n"
                     "  ret i32 %%r\n}\n",
                     tables ? "@ms_tables = external global i8\n" : "", tables ? "@ms_tables" : "null");
}
