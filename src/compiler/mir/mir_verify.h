/* compiler/mir/mir_verify.h: the MIR verifier: structure, SSA dominance, operand types and ownership. A
 * function that fails an earlier stage is not checked by a later one. */
#ifndef MS_COMPILER_MIR_MIR_VERIFY_H
#define MS_COMPILER_MIR_MIR_VERIFY_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_layout.h"

/* One failure: `block` is MIR_NONE when the error is not local to a block. The text lives in the
 * MirVerifyErrors arena. */
typedef struct MirVerifyError {
  MsSpan func;
  MirBlock block;
  MsSpan message;
} MirVerifyError;

MS_LIST_DEFINE(MirVerifyErrorList, mir_verify_error_list, MirVerifyError)

typedef struct MirVerifyErrors {
  MsArena arena;
  MirVerifyErrorList errors;
} MirVerifyErrors;

/* Verifies the whole module; `out` must be zeroed and is released with mir_verify_errors_free. With
 * `require_locs` every instruction needs a source location. True when nothing is wrong. */
MS_NODISCARD MS_NONNULL bool mir_verify_module(const MirModule *module, bool require_locs, MirVerifyErrors *out);
void mir_verify_errors_free(MirVerifyErrors *errors);

/* Appends `func: bN: message`, or `func: message` for a module-level error. */
void mir_verify_error_text(const MirVerifyError *error, MsStrBuild *out);

/* ---- shared by mir_verify.c and mir_verify_types.c ---- */

/* What a check of one function needs: `drops` is mir_needs_drop of every type, built once because the
 * question scans every case of an enum. `arena` holds the error text. */
typedef struct MirVerifyCx {
  const MirModule *m;
  const MirFunc *f;
  const bool *drops;
  MsArena *arena;
  MirLayouts *layouts; /* for the boxed-or-not questions */
} MirVerifyCx;

/* The operand count and the operand and result types `inst` must have: an empty span when it does, else the
 * reason (in cx->arena). */
MsSpan mir_verify_inst_types(const MirVerifyCx *cx, const MirInst *inst);

#endif
