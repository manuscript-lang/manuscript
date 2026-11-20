/* MIR passes: the ownership, cancellation and expansion rewrites between lowering and the
 * backends, ports of crates/ms-mir (exit_drops.rs, expand.rs, ...). Each pass rewrites a module in
 * place, builds everything it adds in the module's arena, and returns whether it changed anything.
 * Run order is the Rust pipeline's: ... unwind, cancel_edges, depth, expand, glue. */
#ifndef MS_MIR_PASS_H
#define MS_MIR_PASS_H

#include "ms/mir.h"
#include "ms/mir_opt.h"

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


/* An empty function with `f`'s signature: a pass that takes a function out of the module to rewrite
 * it leaves this behind, so a recursive call still reads which arguments the callee consumes and
 * whether its result borrows. */
MirFunc mir_func_stand_in(MirModule *m, const MirFunc *f);

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

/* unwind: registers a cleanup for every owned value live across an instruction that can reach a
 * cancellation point or fault, so a cancelled or faulted task releases what its frames own. Only
 * on modules that start tasks. */
bool mir_unwind(MirModule *m);

/* Places the scope-exit cleanup of every Raw function (one that still carries scope markers).
 * False with `error` set to `function: message` when a function's ownership cannot be expressed. */
bool mir_elaborate(MirModule *m, MsBuf *error);

/* The same, and with `cancel_exits` a function of a task program that parks also gets explicit
 * cancel exits when its owners allow them (port of cancel_exit.rs). */
bool mir_elaborate_with(MirModule *m, bool cancel_exits, MsBuf *error);

/* cancel_edges: after every call that can park, test the task's `unwinding` byte and leave the
 * function through one cancel exit that runs the registered cleanups. Only on modules that start
 * tasks; the caller decides whether edges are switched on (`MS_CANCEL_EDGES`). */
bool mir_cancel_edges(MirModule *m);

/* depth: lowers `depth.enter`, the stack-depth check of a recursive function, to `stack.low`, memory
 * operations and a call of a grow shim. Run after unwind. Returns whether there was one. */
bool mir_depth_lower(MirModule *m);

/* count_ops: a call of `msrt_ops_add(n)` at the head of every block, n its instruction count plus
 * one. */
void mir_count_ops(MirModule *m);

/* frames: a flag per value of `f` (`nvalues` entries, in `arena`), set for the `iface.borrow` results
 * and the closure objects that may live in `f`'s frame; NULL when there is none of either. */
bool *mir_framed_iface_borrows(MsArena *arena, const MirModule *m, const MirFunc *f);
bool *mir_framed_closure_objects(MsArena *arena, const MirModule *m, const MirFunc *f);

/* copies: whether a value of `t` holds a runtime object, and a line `func<TAB>type<TAB>file:line`
 * for every clone that copies one. */
bool mir_holds_object(const MirModule *m, MirTy t);
void mir_object_copies(const MirModule *m, MsBuf *out);

/* slot_scope: per value of `f` (`nvalues` entries, in `arena`), the block a stack `slot` is confined
 * to (see mir_slot_scope.c), MIR_NONE for every other value; NULL when `f` has no slot. */
MirBlock *mir_confined_slots(MsArena *arena, const MirModule *m, const MirFunc *f);

/* ---- pipeline ---- */

typedef struct MirPipelineOptions {
    bool cancel_edges; /* explicit cancel exits (`MS_CANCEL_EDGES`) */
    bool checks;       /* the bounds and none checks `expand` makes explicit */
    bool count_ops;    /* count executed operations (`ms build --count-ops`) */
    bool verify;       /* verify the module after each step, as the Rust debug build does */
} MirPipelineOptions;

/* Right after lowering: places the scope-exit cleanup of every Raw function. False with `error` set
 * to the message. */
bool mir_pipeline_prepare(MirModule *m, const MirPipelineOptions *o, MsBuf *error);

/* Between prepare and finish: the optimizer for `level` (opt_pipeline.c), re-verifying after every
 * pass when `o->verify` is set. False with `error` set to the failing pass and the module. */
bool mir_pipeline_optimize(MirModule *m, MirOptLevel level, const MirPipelineOptions *o, MsBuf *error);

/* After the optimizer: count_ops when on, unwind, cancel_edges when on, depth, expand, glue. `glue` receives what glue
 * made, which backends look up. */
struct MirGlue;
bool mir_pipeline_finish(MirModule *m, const MirPipelineOptions *o, struct MirGlue *glue,
                         MsBuf *error);

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
/* Makes the function `(list, from)` behind `list.release` for list type `ty`: it drops the elements from index `from`
 * (a negative one counts from the start) and frees the block of an owned list (capacity not 0). It holds `drop` ops
 * that `lower_ops` still has to rewrite. */
uint32_t mir_glue_list_release(MirModule *m, MirTy ty);

/* Marks in `framed` (zeroed, one flag per value of `f`) the closure objects `f` keeps in its stack
 * frame: a closure that owns no resource, only dropped, called, or lent to calls that neither keep
 * nor return it. Glue picks the framed drop for them and backends allocate them in the frame. */
void mir_framed_closures(const MirModule *m, const MirFunc *f, bool *framed);

/* glue: makes the drop and clone function of every type whose drop is a walk of its fields, the
 * slot and block functions descriptors and interfaces point at, and the closure object
 * functions. Returns whether anything was made. */
bool mir_glue(MirModule *m, MirGlue *g);

/* glue plus expand_owned, repeated until nothing new is wanted. The last step before backends. */
void mir_glue_run_and_expand(MirModule *m, MirGlue *g);

/* lower_ops: the last pass before the emitters. Rewrites clone, drop, move.out and forget into
 * renamed uses, runtime calls and glue calls (proposals/lower-ops-to-runtime-calls.md, stage 1). */
void mir_lower_ops(MirModule *m, const MirGlue *glue);

#endif
