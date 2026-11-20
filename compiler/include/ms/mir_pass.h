/* MIR passes: the ownership, cancellation and expansion rewrites between lowering and the
 * backends, ports of crates/ms-mir (exit_drops.rs, expand.rs, ...). Each pass rewrites a module in
 * place, builds everything it adds in the module's arena, and returns whether it changed anything.
 * Run order is the Rust pipeline's: ... unwind, cancel_edges, depth, expand, glue. */
#ifndef MS_MIR_PASS_H
#define MS_MIR_PASS_H

#include "ms/mir.h"

/* ---- shared helpers ---- */

/* The `extern` named `name`, declared on first use with the given borrowed parameters. */
uint32_t mir_extern_get(MirModule *m, const char *name, const MirTy *params, uint32_t nparams,
                        MirTy ret, bool leaf, MirRole role);

/* Whether dropping a value of `ty` only returns memory (no file, connection or closure). */
bool mir_drops_plain_memory(const MirModule *m, MirTy ty);

/* A copy of `args` in the module's arena. */
MirValue *mir_args_copy(MirModule *m, const MirValue *args, uint32_t n);

/* Instruction and immediate constructors; the argument array is borrowed, so pass an arena copy. */
MirInst mir_inst(MirOp op, MirImm imm, MirValue res, MirLoc loc, MirValue *args, uint32_t n);
MirImm mir_imm_none(void);
MirImm mir_imm_int(int64_t v);
MirImm mir_imm_cc(MirCc cc);
MirImm mir_imm_ext(uint32_t ext);


/* ---- passes ---- */

/* exit_drops: gates the plain-memory drops that end the program entry (and a `main` it calls once)
 * behind `msrt_exit_frees`. */
void mir_exit_drops(MirModule *m);

/* expand: checked list accesses, `opt.unwrap` and `list.push` become explicit compares, fault
 * blocks and unchecked operations. With `checks` off the bounds and none checks are left out. */
bool mir_expand(MirModule *m, bool checks);

/* expand_owned: the ownership shorthands (`alt.own`, `alt.unbox`, `alt.release`, `type.release`,
 * `opt.unbox`, `opt.unwrap`) become plain loads, drops and frees, so backends lower only
 * primitives. Run after unwind, the last pass that reads them. */
bool mir_expand_owned_needed(const MirModule *m);
bool mir_expand_owned(MirModule *m);

#endif
