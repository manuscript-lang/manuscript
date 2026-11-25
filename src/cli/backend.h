/* cli/backend.h: the back end as one call: a checked program in, LLVM IR text out. */
#ifndef MS_CLI_BACKEND_H
#define MS_CLI_BACKEND_H

#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/emit/emit_tables.h"

typedef struct BackendOptions {
  bool optimize; /* run the MIR optimiser; only `ms emit` leaves it off, to show the MIR before it */
  bool compact;  /* the MIR optimiser inlines only small callees (Debug: a smaller module compiles faster) */
  bool verify;   /* verify the module after every pass of the pipeline */
  bool verify_final; /* verify it once, when the passes are done (cheaper than `verify`) */
  bool tests;    /* start at the test entry (ms_lower_tests) instead of `main` */
  bool bench;    /* with `tests`: the program's `bench` blocks run as the tests (ms_lower_benches) */
  bool count_ops; /* each block counts its operations (`ms bench --ops`) */
  uint32_t wide_leaves; /* a value of more leaves than this lives in a stack cell; 0 for never */
  bool wide_hide;       /* keep those cells out of LLVM's reach (volatile leaf loads): Debug frames, not optimization */
  bool poison_slots;    /* EmitOptions.poison_slots */
  uint32_t units;       /* EmitOptions.units: the most modules ms_backend_compile writes; 0 for one */
  size_t unit_bytes;    /* EmitOptions.unit_bytes */
  MsSpan cranelift;     /* the Cranelift library to write the object with (Debug), or empty for the LLVM route */
} BackendOptions;

/* A compiled program kept for the fault tables: the renamed module and what the tables need to know of it. */
typedef struct BackendProgram {
  MirModule module;
  MsArena arena;
  EmitTableInfo tables;
  MsStrBuild object; /* the finished object file when Cranelift wrote it; `ir` is then empty */
  bool native;
} BackendProgram;

/* As ms_backend_ir, with the entry point and source places the fault tables need; `out` then holds the module the
 * link step reads them from, and is released with ms_backend_program_free. `ir` is an array of EMIT_MAX_UNITS new
 * builders: with `options->units` above 1 a big program is written as several modules (see emit_module), and
 * `*units` says how many; module 0 has the entry point. */
bool ms_backend_compile(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options,
                        MsStrBuild *ir, uint32_t *units, BackendProgram *out, MsStrBuild *why);
void ms_backend_program_free(BackendProgram *program);

/* Lowers the program from the `main` of module `entry_module`, runs the MIR passes and emits LLVM IR text
 * for the program, with the C entry point, into `ir`. On failure returns false and `why` says what failed. */
bool ms_backend_ir(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MsStrBuild *ir,
                   MsStrBuild *why);

#endif
