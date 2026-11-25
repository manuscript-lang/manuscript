/* compiler/emit_cl/cl_cx.h: the state of lowering one MIR function to Cranelift IR, and the helpers every part of
 * the lowering shares.
 *
 * A MIR value is a run of leaves, as in compiler/emit/emit_cx.h: one Cranelift value each. Registers hold i64,
 * f64 and i8 (a boolean); sized integers and Float32 are widened in registers and narrowed only in memory. A
 * value of at most CL_DIRECT_BYTES travels as its leaves; a larger one travels as the address of a copy. A result of
 * more than one leaf is written through a hidden first parameter. Checked operations end a Cranelift block with a
 * branch to a cold block that posts the fault. */
#ifndef MS_COMPILER_EMIT_CL_CL_CX_H
#define MS_COMPILER_EMIT_CL_CL_CX_H

#include "compiler/emit_cl/cranelift_inproc.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"
#include "compiler/mir/mir_layout.h"

#define CL_DIRECT_BYTES 16
/* Argument positions whose copy slots calls share. */
#define CL_SHARED_ARGS 32u

/* The module-wide state: the declared functions, runtime functions and data, shared by every function. */
typedef struct ClModule {
  const MirModule *module;
  const MirData *data;
  const MirGlue *glue;
  MirLayouts *layouts;
  ms_cl *cl;
  ms_cl_func *funcs;     /* per MIR function */
  ms_cl_func *externs;   /* per extern; UINT32_MAX id until first used */
  bool *extern_made;
  /* The runtime functions the lowering calls itself (fault posts, `msrt_free`), declared on first use. */
  struct ClNamed {
    const char *name;
    ms_cl_func func;
  } named[24];
  uint32_t nnamed;
  const uint32_t *scope_base; /* per function: module-wide index of its first scope */
  uint32_t total_scopes;
} ClModule;

/* The fault functions the lowering itself calls; each takes the listed number of i64 arguments. */
typedef enum ClPost {
  CL_POST_INT_OVERFLOW, CL_POST_INT_RANGE, CL_POST_DIV_ZERO, CL_POST_REM_ZERO, CL_POST_DIV_OVERFLOW,
  CL_POST_INDEX, CL_POST_UNWRAP_NONE, CL_POST_FAULT_POSTED, CL_POST_COUNT
} ClPost;

typedef struct ClCx {
  ClModule *mod;
  const MirModule *module;
  const MirFunc *func;
  uint32_t index;          /* the function's id */
  MirLayouts *layouts;
  ms_cl_fn *fb;
  const char *why;         /* the reason an instruction cannot be lowered; static text */
  ms_cl_val *regs;         /* the leaves of every value, one after another; see `first` */
  uint32_t *first;         /* per value: index of its first leaf in `regs` */
  ms_cl_block *blocks;     /* per MIR block */
  ms_cl_block cur;         /* the Cranelift block instructions go to: a check continues in a new one */
  ms_cl_val result_area;   /* the hidden result pointer, when the function has one */
  bool has_result_area;
  bool places;             /* tag each instruction with its source line for the fault tables */
  uint32_t scope_base;     /* module-wide index of the first scope of `func` */
  uint32_t body_scope;     /* the scope number of `func`'s own body */
  /* The stack areas calls share: a copy slot per argument position, and one result area, each made on first use. */
  ms_cl_slot shared[CL_SHARED_ARGS], area;
  uint32_t shared_bytes[CL_SHARED_ARGS], area_bytes;
  bool shared_made[CL_SHARED_ARGS], area_made;
  uint32_t cur_block, cur_index; /* the MIR instruction being lowered; index == insts.len for the terminator */
} ClCx;

/* ---- leaves (cl_leaf.c) ---- */

MsSpan cl_leaves(ClCx *cx, MirTy type);
MsSpan cl_value_leaves(ClCx *cx, MirValue value);
MirTy cl_value_type(const ClCx *cx, MirValue value);
/* The register type of a leaf, and of the single leaf of a one-leaf value. */
ms_cl_type cl_reg_type(MirLeaf leaf);
ms_cl_type cl_value_reg_type(ClCx *cx, MirValue value);
bool cl_is_indirect(ClCx *cx, MirTy type);
uint32_t cl_slot_bytes(ClCx *cx, MirTy type);
/* The Cranelift value of leaf `leaf` of `value`, and setting it. */
ms_cl_val cl_get(const ClCx *cx, MirValue value, uint32_t leaf);
void cl_set(ClCx *cx, MirValue value, uint32_t leaf, ms_cl_val reg);
/* The one value of a one-leaf operand. */
ms_cl_val cl_arg(const ClCx *cx, const MirInst *inst, uint32_t arg);
/* The i64 constant `k`. */
ms_cl_val cl_const(ClCx *cx, int64_t k);
/* Widens a loaded leaf to its register type and narrows a register for a store. */
ms_cl_val cl_widen(ClCx *cx, MirLeaf leaf, ms_cl_val loaded);

/* ---- memory (cl_mem.c) ---- */

/* Loads leaf `leaf` of `dst` from `base + offset`, and stores it. */
void cl_load_leaf(ClCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, ms_cl_val base, int32_t offset);
void cl_store_leaf(ClCx *cx, MirLeaf leaf, MirValue src, uint32_t index, ms_cl_val base, int32_t offset);
/* Reads (`load`) or writes the leaves of `value` at `base`. */
void cl_leaves_at(ClCx *cx, MirValue value, ms_cl_val base, bool load);
/* A zeroed stack slot of `bytes` bytes: its address. */
ms_cl_val cl_slot(ClCx *cx, uint32_t bytes);
/* The leaf `dst` leaf `to` takes leaf `from` of `src`, converting between leaf types when they differ. */
void cl_copy_leaf(ClCx *cx, MirValue dst, uint32_t to, MirValue src, uint32_t from);
void cl_zero_leaf(ClCx *cx, MirValue dst, uint32_t index, MirLeaf leaf);

/* ---- operations by family; each sets `*handled` and returns false only when `cx->why` is set ---- */

bool cl_scalar_op(ClCx *cx, const MirInst *inst, bool *handled);
bool cl_checked_op(ClCx *cx, const MirInst *inst, bool *handled);
bool cl_memory_op(ClCx *cx, const MirInst *inst, bool *handled);
bool cl_call_op(ClCx *cx, const MirInst *inst, bool *handled);
/* Sizes the shared stack areas of the calls of the function; call once before lowering it. */
void cl_frame_areas(ClCx *cx);
/* The type a runtime function takes or returns a leaf in. */
ms_cl_type cl_rt_leaf_type(MirLeaf leaf, bool is_c);

/* Ends the current block with a check: when `condition` (an i8) holds the program calls fault function `post` with the
 * i64 `args` and leaves by the exit of the instruction being lowered, or ends when it has none; otherwise it
 * continues in a new block. */
void cl_fault_if(ClCx *cx, ms_cl_val condition, ClPost post, const ms_cl_val *args, uint32_t nargs);

/* ---- the module (cl_module.c) ---- */

/* The Cranelift function of runtime function `external`, declared on first use. */
ms_cl_func cl_extern_func(ClModule *mod, uint32_t external);
/* A runtime function the lowering calls by name: the module's own declaration when it lists one, else `nargs` i64
 * parameters and an i64 result when `has_result`. */
ms_cl_func cl_runtime_func(ClModule *mod, const char *name, uint32_t nargs, bool has_result);
ms_cl_func cl_post_func(ClModule *mod, ClPost post);

#endif
