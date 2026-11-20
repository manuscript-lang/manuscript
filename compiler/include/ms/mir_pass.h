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


/* Whether the module starts tasks (some extern has the `spawns_task` role): only then do the
 * cancellation passes rewrite anything. */
bool mir_starts_tasks(const MirModule *m);

/* Per function: whether it can reach a cancellation point (a poll, an indirect call, a runtime
 * call that is not a known leaf), directly or through a callee. `nfuncs` entries, in `arena`. */
bool *mir_parking_funcs(MsArena *arena, const MirModule *m);

/* Whether `inst` can reach a cancellation point; `parks` is `mir_parking_funcs`' result. */
bool mir_inst_parks(const MirModule *m, const bool *parks, const MirInst *inst);

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

/* cancel_edges: after every call that can park, test the task's `unwinding` byte and leave the
 * function through one cancel exit that runs the registered cleanups. Only on modules that start
 * tasks; the caller decides whether edges are switched on (`MS_CANCEL_EDGES`). */
bool mir_cancel_edges(MirModule *m);

/* ---- glue ---- */

/* The kinds of generated helper functions a backend calls instead of writing its own. */
typedef enum MirGlueKind {
    MG_DROP, MG_CLONE, MG_CLOSURE_DROP, MG_CLOSURE_DROP_FRAMED, MG_CLOSURE_DROP_FROM,
    MG_CLOSURE_CLONE, MG_BLOCK_DROP, MG_BLOCK_CLONE, MG_SLOT_DROP, MG_SLOT_COPY
} MirGlueKind;

/* One made function: `ty` is the type it works on (MIR_VOID for the closure kinds, which carry
 * the closure function in `a` and, for `closure_drop_from`, the capture in `b`). */
typedef struct MirGlueEntry {
    uint8_t kind;
    uint32_t a, b;
    MirTy ty;
    uint32_t func;
} MirGlueEntry;

/* Everything the glue passes made, which backends look up by kind and type (`Module::drop_glue`,
 * `clone_glue`, `addr_glue`, `glue_bodies`). Lives in the module's arena. */
typedef struct MirGlue {
    MirGlueEntry *v;
    uint32_t n, cap;
    uint32_t *bodies; /* the bodies the deep-recursion wrappers call */
    uint32_t nbodies, cbodies;
} MirGlue;

/* The function made for `kind` of `ty` (and closure `a`, capture `b`), or MIR_NONE. */
uint32_t mir_glue_find(const MirGlue *g, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b);

/* glue: makes the drop and clone function of every type whose drop is a walk of its fields, the
 * slot and block functions descriptors and interfaces point at, and the closure object
 * functions. Returns whether anything was made. */
bool mir_glue(MirModule *m, MirGlue *g);

/* glue plus expand_owned, repeated until nothing new is wanted. The last step before backends. */
void mir_glue_run_and_expand(MirModule *m, MirGlue *g);

#endif
