/* compiler/link/llvm_inproc.h: LLVM IR text to optimized IR and to an object or assembly file in this process, through
 * the C API of the bundled shared libLLVM, which is loaded by path when first used. */
#ifndef MS_COMPILER_LINK_LLVM_INPROC_H
#define MS_COMPILER_LINK_LLVM_INPROC_H

#include "base/strbuild.h"

typedef struct LlvmSettings {
  MsSpan library;      /* absolute path of the shared libLLVM */
  MsSpan triple;
  const char *pipeline; /* the optimizer's pass pipeline (LLVM's textual syntax); NULL to skip the optimizer */
  bool vectorize;
  bool verify;         /* check the IR after every pass */
  int codegen_level;   /* 0 to 3, the llc -O level */
  bool fast_codegen;   /* a cheaper code generator for Debug builds: the basic register allocator and no machine
                          scheduler. The frames come out the same size. FastISel is not used: it attributes some
                          instructions to other source lines, which changes the lines of a fault trace. */
  bool assembly;       /* write assembly text instead of an object */
} LlvmSettings;

typedef struct LlvmBuffer {
  const char *data;
  size_t size;
  void *handle;
} LlvmBuffer;

/* Loads the library (once) and compiles `ir`. On failure `why` holds the message. Safe to call from several threads once
 * `llvm_load` has loaded the library, as long as the compiles running at once use the same `codegen_level` and
 * `fast_codegen`: the code generator's options are process-wide. */
MS_NODISCARD MS_NONNULL bool llvm_compile(const LlvmSettings *settings, MsSpan ir, LlvmBuffer *out, MsStrBuild *why);

/* Loads the library at `path` (once); on failure `why` holds the reason. Call it before compiling from several threads. */
MS_NODISCARD MS_NONNULL bool llvm_load(MsSpan path, MsStrBuild *why);

/* Whether the library at `path` loads and has the C API ms uses; the library stays loaded for llvm_compile. */
MS_NODISCARD bool llvm_usable(MsSpan path);

void llvm_buffer_free(LlvmBuffer *buffer);

#endif
