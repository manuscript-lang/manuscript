/* compiler/link/object.h: LLVM IR text to an object file with the pinned `opt` and `llc`, run as child
 * processes. */
#ifndef MS_COMPILER_LINK_OBJECT_H
#define MS_COMPILER_LINK_OBJECT_H

#include "base/strbuild.h"
#include "compiler/emit/emit_tables.h"

typedef struct ObjectOptions {
  MsSpan opt;       /* the `opt` executable */
  MsSpan llc;       /* the `llc` executable */
  MsSpan llvm;      /* the shared libLLVM to compile in this process; empty to run `opt` and `llc` instead */
  MsSpan directory; /* an existing directory for the intermediate files; they are removed afterwards */
  bool speed;       /* optimize: -O3, or -O2 with `debug`; otherwise the IR goes straight to the code generator at -O0 */
  bool debug;       /* with `speed`: a Debug build, which uses -O2 */
  bool vectorize;   /* with `speed`: allow LLVM's loop and SLP vectorizers */
  bool verify;      /* check the IR after every pass */
  const MirModule *module;        /* with `tables`: the renamed module (emit_name_symbols) */
  const EmitTableInfo *tables;    /* NULL for no fault tables; the program then needs emit_entry_main(tables=true) */
  uint32_t unit, units;           /* this is module `unit` of a program written as `units` modules (see emit_module) */
} ObjectOptions;

/* What phase one of a module leaves for phase two: the assembly it generated (in-process; the child processes leave it
 * in a file). */
typedef struct ObjectCode {
  const char *data;
  size_t size;
  void *handle;
} ObjectCode;

/* Releases what link_generate left in `code` (link_finish does it itself). */
void link_discard(ObjectCode *code);

/* Compiles `ir` to the object file `object`. On failure `why` gets the tool's name and its output. */
MS_NODISCARD MS_NONNULL bool link_make_object(const ObjectOptions *options, MsSpan ir, MsSpan object,
                                              MsStrBuild *why);

/* The same in two phases, so the modules of one program can run each phase at once on several threads. LLVM's code
 * generator reads process-wide options (a different register allocator for each phase), so every module must finish
 * link_generate before any starts link_finish. Without fault tables link_generate writes `object` and link_finish
 * has nothing to do; with them link_generate stops at assembly, and link_finish adds the tables and writes `object`. */
MS_NODISCARD MS_NONNULL bool link_generate(const ObjectOptions *options, MsSpan ir, MsSpan object, ObjectCode *code,
                                           MsStrBuild *why);
MS_NODISCARD MS_NONNULL bool link_finish(const ObjectOptions *options, MsSpan object, ObjectCode *code, MsStrBuild *why);

#endif
