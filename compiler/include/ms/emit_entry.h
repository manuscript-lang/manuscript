/* The program entry the C back end adds around a module's entry function. */
#ifndef MS_EMIT_ENTRY_H
#define MS_EMIT_ENTRY_H

#include "ms/mir.h"

/* Gives every function a symbol of its own, before either emitter runs: the entry function becomes
 * `ms_entry` (the C `main` calls it) and any function that is not exported gets its index appended. */
void mir_name_symbols(MirModule *m);

/* Appends the C `main` that calls `msrt_start` with the entry function: QBE text, or LLVM IR when
 * `llvm`. With `tables` (QBE) it hands the runtime the symbol `ms_tables`. Nothing when the module has
 * no entry. */
void mir_emit_entry_main(const MirModule *m, bool llvm, bool tables, MsBuf *out);

#endif
