/* driver/backend.h: the back end as one call: a checked program in, LLVM IR text out. */
#ifndef MS_DRIVER_BACKEND_H
#define MS_DRIVER_BACKEND_H

#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/emit/emit_tables.h"

typedef struct BackendOptions {
  bool optimize; /* the full optimiser pipeline instead of the small one */
  bool verify;   /* verify the module after every pass */
  bool tests;    /* start at the test entry (ms_lower_tests) instead of `main` */
  bool bench;    /* with `tests`: the program's `bench` blocks run as the tests (ms_lower_benches) */
  bool count_ops; /* each block counts its operations (`ms bench --ops`) */
} BackendOptions;

/* A compiled program kept for the fault tables: the renamed module and what the tables need to know of it. */
typedef struct BackendProgram {
  MirModule module;
  MsArena arena;
  EmitTableInfo tables;
} BackendProgram;

/* As ms_backend_ir, with the entry point and source places the fault tables need; `out` then holds the module the
 * link step reads them from, and is released with ms_backend_program_free. */
bool ms_backend_compile(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options,
                        MsStrBuild *ir, BackendProgram *out, MsStrBuild *why);
void ms_backend_program_free(BackendProgram *program);

/* Lowers the program from the `main` of module `entry_module`, runs the MIR passes and emits LLVM IR text
 * for the program, with the C entry point, into `ir`. On failure returns false and `why` says what failed. */
bool ms_backend_ir(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MsStrBuild *ir,
                   MsStrBuild *why);

#endif
