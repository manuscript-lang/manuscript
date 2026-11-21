/* libms LLVM emitter: writes LLVM IR text from MIR, for debug and release builds. The caller runs the
 * LLVM tools on the text and links. What it cannot write is reported. */
#ifndef MS_EMIT_LLVM_H
#define MS_EMIT_LLVM_H

#include "ms/mir.h"
#include "ms/mir_data.h"
#include "ms/mir_pass.h"
#include "ms/mir_tables.h"

/* Appends one LLVM module holding every function of `m` to `out`, with the static data of `data`
 * (`mir_data_build` after glue; NULL for a module with none) and the glue the closure objects
 * point at (`mir_glue_run_and_expand`; NULL for a module with no closures). Returns false when something
 * cannot be written yet, with one line per function and reason appended to `why` (`out` is then
 * partial). */
bool mir_emit_llvm(const MirModule *m, const MirData *data, const MirGlue *glue, MsBuf *out, MsBuf *why);

/* How `mir_emit_llvm_program` writes a module. */
typedef struct MirLlvmOptions {
    bool export_all;   /* every function gets an external symbol, which the tables unit names */
    bool places;       /* a source place on every instruction, for the fault tables */
    bool slot_scopes;  /* mark where each stack slot that lives in one block starts and stops living, so LLVM
                          may share its stack space. The markers take the form the pinned LLVM reads (one
                          pointer argument); an older clang rejects it. */
    bool poison_slots; /* fill each stack slot that lives in one block with 0xDD where that block ends, so a
                          pointer that outlives the slot reads garbage in every build */
} MirLlvmOptions;

/* `mir_emit_llvm` as `how` says. The three functions below are this with one option set. */
bool mir_emit_llvm_program(const MirModule *m, const MirData *data, const MirGlue *glue, const MirLlvmOptions *how,
                           MsBuf *out, MsBuf *why);

/* The same with `export_all`: every function gets an external symbol, which the tables unit of
 * `mir_emit_llvm_main` names. */
bool mir_emit_llvm_with(const MirModule *m, const MirData *data, const MirGlue *glue, bool export_all,
                        MsBuf *out, MsBuf *why);

/* `mir_emit_llvm` with a source place on every instruction (line tables only, the column is the module-wide
 * scope), for the fault tables ms_asm_tables builds from `clang -S`. */
bool mir_emit_llvm_places(const MirModule *m, const MirData *data, const MirGlue *glue, MsBuf *out, MsBuf *why);

/* Appends the program's `main` and the fault tables (`mir_fault_tables`, one entry per function in
 * module order) as one more module: `main` hands the entry function and the table to `msrt_start`.
 * False when the module has no entry function. */
bool mir_emit_llvm_main(const MirModule *m, const MirTables *tables, MsBuf *out);

#endif
