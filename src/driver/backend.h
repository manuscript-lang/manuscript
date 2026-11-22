/* driver/backend.h: the back end as one call: a checked program in, LLVM IR text out. */
#ifndef MS_DRIVER_BACKEND_H
#define MS_DRIVER_BACKEND_H

#include "base/strbuild.h"
#include "compiler/check/program.h"

typedef struct BackendOptions {
  bool optimize; /* the full optimiser pipeline instead of the small one */
  bool verify;   /* verify the module after every pass */
} BackendOptions;

/* Lowers the program from the `main` of module `entry_module`, runs the MIR passes and emits LLVM IR text
 * for the program, with the C entry point, into `ir`. On failure returns false and `why` says what failed. */
bool ms_backend_ir(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MsStrBuild *ir,
                   MsStrBuild *why);

/* The same lowering and passes up to the emitter, with the module printed as MIR text into `text`. */
bool ms_backend_mir(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MsStrBuild *text,
                    MsStrBuild *why);

#endif
