/* compiler/link/object.h: LLVM IR text to an object file with the pinned `opt` and `llc`, run as child
 * processes. */
#ifndef MS_COMPILER_LINK_OBJECT_H
#define MS_COMPILER_LINK_OBJECT_H

#include "base/strbuild.h"

typedef struct ObjectOptions {
  MsSpan opt;       /* the `opt` executable */
  MsSpan llc;       /* the `llc` executable */
  MsSpan directory; /* an existing directory for the intermediate files; they are removed afterwards */
  bool speed;       /* optimize (O3); otherwise the IR goes straight to the code generator at -O0 */
  bool vectorize;   /* with `speed`: allow LLVM's loop and SLP vectorizers */
  bool verify;      /* check the IR after every pass */
} ObjectOptions;

/* Compiles `ir` to the object file `object`. On failure `why` gets the tool's name and its output. */
MS_NODISCARD MS_NONNULL bool link_make_object(const ObjectOptions *options, MsSpan ir, MsSpan object,
                                              MsStrBuild *why);

#endif
