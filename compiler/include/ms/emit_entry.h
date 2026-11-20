/* The program entry the C back end adds around a module's entry function. */
#ifndef MS_EMIT_ENTRY_H
#define MS_EMIT_ENTRY_H

#include "ms/mir.h"

/* Renames the entry function, before either emitter runs, so its name does not clash with `main`. */
void mir_name_entry(MirModule *m);

/* Appends the C `main` that calls `msrt_start` with the entry function: QBE text, or LLVM IR when
 * `llvm`. With `tables` (QBE) it hands the runtime the symbol `ms_tables`. Nothing when the module has
 * no entry. */
void mir_emit_entry_main(const MirModule *m, bool llvm, bool tables, MsBuf *out);

#endif
