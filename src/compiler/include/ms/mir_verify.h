/* The MIR verifier (verify.rs, verify/types.rs): structure, SSA dominance, operand types and
 * ownership. Errors read exactly as the Rust verifier prints them, so the two can be compared. */
#ifndef MS_MIR_VERIFY_H
#define MS_MIR_VERIFY_H

#include "ms/mir.h"
#include "ms_rt/safe.h"

/* One failure: `block` is MIR_NONE when the error is not local to a block. The strings live in
 * the MirVerifyErrors arena. */
typedef struct MirVerifyError {
    MsStr func;
    MirBlock block;
    MsStr message;
} MirVerifyError;

typedef struct MirVerifyErrors {
    MsArena arena;
    MirVerifyError *errors;
    uint32_t count, cap;
} MirVerifyErrors;

/* Verifies the whole module; `out` must be zeroed and is freed with mir_verify_errors_free. With
 * `require_locs` every instruction needs a source location. Returns true when nothing is wrong. */
MS_NODISCARD bool mir_verify_module(const MirModule *m, bool require_locs, MirVerifyErrors *out);
void mir_verify_errors_free(MirVerifyErrors *errors);

/* Appends `func: bN: message`, or `func: message` for a module-level error. */
void mir_verify_error_text(const MirVerifyError *e, MsBuf *out);

/* ---- shared by mir_verify.c and mir_verify_types.c ---- */

/* What a check of one function needs: `drops` is mir_needs_drop of every type, built once because
 * the question scans every case of an enum. `arena` holds the error text. */
typedef struct MirVerifyCx {
    const MirModule *m;
    const MirFunc *f;
    const bool *drops;
    MsArena *arena;
} MirVerifyCx;

/* The operand count and the operand and result types `in` must have: NULL when it does, else the
 * reason (in cx->arena). */
const char *mir_verify_inst_types(const MirVerifyCx *cx, const MirInst *in);

#endif
