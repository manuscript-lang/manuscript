/* compiler/mir/mir_pass.h: helpers shared by the MIR passes between lowering and the emitter, and the
 * per-function facts the emitter reads (frames, confined slots). A pass rewrites a module in place, builds
 * everything it adds in the module's arena, and returns whether it changed anything. */
#ifndef MS_COMPILER_MIR_MIR_PASS_H
#define MS_COMPILER_MIR_MIR_PASS_H

#include "compiler/mir/mir.h"

/* ---- shared helpers ---- */

/* The extern named `name`, declared on first use with the given borrowed parameters. */
uint32_t mir_extern_get(MirModule *module, MsSpan name, const MirTy *params, uint32_t nparams, MirTy ret,
                        bool leaf, MirRole role);

/* Whether dropping a value of `ty` only returns memory (no file, connection or closure). */
bool mir_drops_plain_memory(const MirModule *module, MirTy ty);

/* A copy of `args` in the module's arena. */
MirValue *mir_args_copy(MirModule *module, const MirValue *args, uint32_t count);

/* Instruction and immediate constructors; the argument array is borrowed, so pass an arena copy. */
MirInst mir_inst(MirOp op, MirImm imm, MirValue res, MirLoc loc, MirValue *args, uint32_t count);
MirImm mir_imm_none(void);
MirImm mir_imm_int(int64_t value);
MirImm mir_imm_cc(MirCc cc);
MirImm mir_imm_ext(uint32_t external);

/* Appends to `block` an instruction with the given operands (copied into the module arena) and, unless `ty` is
 * MIR_NONE, a fresh result of that type; returns the result or MIR_NONE. */
MirValue mir_block_emit(MirModule *module, MirFunc *func, MirBlockData *block, MirOp op, const MirValue *args,
                        uint32_t count, MirImm imm, MirTy ty, MirLoc loc);

/* Replaces the instruction list of `block` by `insts`, releasing the old one; the list is moved. */
void mir_block_set_insts(MirBlockData *block, MirInstList *insts);

/* Every use of `from` in `func` (operands, conditions and block arguments) becomes `to`, which has the same
 * type. */
void mir_func_replace_uses(MirFunc *func, MirValue from, MirValue to);

/* An empty function with `func`'s signature: a pass that takes a function out of the module to rewrite it
 * leaves this behind, so a recursive call still reads which arguments the callee consumes and whether its
 * result borrows. */
MirFunc mir_func_stand_in(MirModule *module, const MirFunc *func);

/* Whether the module starts tasks (some extern has the `spawns_task` role): only then do the cancellation
 * passes rewrite anything. */
bool mir_starts_tasks(const MirModule *module);

/* Per function: whether it can reach a cancellation point (a poll, an indirect call, a runtime call that is
 * not a known leaf), directly or through a callee. One entry per function, in `arena`. */
bool *mir_parking_funcs(MsArena *arena, const MirModule *module);

/* Whether `inst` can reach a cancellation point; `parks` is mir_parking_funcs' result. */
bool mir_inst_parks(const MirModule *module, const bool *parks, const MirInst *inst);

/* ---- facts the emitter reads ---- */

/* A flag per value of `func` (in `arena`), set for the `iface.borrow` results that may live in the frame
 * (used only by drops and by calls that do not return a view of them); NULL when there is none. */
bool *mir_framed_iface_borrows(MsArena *arena, const MirModule *module, const MirFunc *func);

/* The same for closure objects of closures that close nothing and that only drops and borrowing calls use. */
bool *mir_framed_closures(MsArena *arena, const MirModule *module, const MirFunc *func);

/* Whether a runtime call's result or the runtime may keep the address of an argument beyond the call. */
bool mir_extern_pins_argument(const MirExtern *external);

/* Which stack `slot`s of `func`, and which values flagged in `values` (NULL for none; values kept in a stack cell),
 * may share storage. Each is an object, numbered from 0 in value order: `value[object]` is its value and
 * `ordinal[value]` its number (MIR_NONE for a value that is not one). Row `o` of `conflict` (`words` words per row)
 * has a bit for every object that is live where `o` is made or written, which `o` must not share storage with.
 * A value kept in a cell is made where it is defined, and a block parameter where each predecessor ends. An object
 * with `shareable` false (a slot whose address is stored, returned, passed to a block or kept by the runtime)
 * keeps its place for the whole function. False when `func` has no object or is too large to analyse. */
typedef struct MirCellDeath {
  uint32_t block, index, object; /* the instruction after which `object` is not read again on any path out of the block */
} MirCellDeath;

typedef struct MirCellMap {
  uint32_t nobjects, words;
  const uint32_t *value, *ordinal;
  const uint64_t *conflict;
  const bool *shareable;
  const MirCellDeath *deaths; /* filled when the caller asks (MS_POISON_SLOTS), else NULL */
  uint32_t ndeaths;
} MirCellMap;

bool mir_cell_conflicts(MsArena *arena, const MirModule *module, const MirFunc *func, const bool *values,
                        bool want_deaths, MirCellMap *map);

#endif
