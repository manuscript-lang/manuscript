/* compiler/emit_cl/cl_cx.h: the state of lowering one MIR function to Cranelift IR, and the helpers every part of
 * the lowering shares.
 *
 * A MIR value is a run of leaves, as in compiler/emit/emit_cx.h: one Cranelift value each. Registers hold i64,
 * f64 and i8 (a boolean); sized integers and Float32 are widened in registers and narrowed only in memory. A
 * value of at most CLX_DIRECT_BYTES travels as its leaves; a larger one travels as the address of a copy. A result of
 * more than one leaf is written through a hidden first parameter. Checked operations end a Cranelift block with a
 * branch to a cold block that posts the fault. */
#ifndef MS_COMPILER_EMIT_CL_CL_CX_H
#define MS_COMPILER_EMIT_CL_CL_CX_H

#include "compiler/emit/emit_tables.h"
#include "compiler/emit_cl/cranelift_inproc.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"
#include "compiler/mir/mir_layout.h"

#define CLX_DIRECT_BYTES 16
/* Argument positions whose copy slots calls share. */
#define CLX_SHARED_ARGS 32u

/* The module-wide state: the declared functions, runtime functions and data, shared by every function. */
typedef struct ClModule {
  const MirModule *module;
  const MirData *data;
  const MirGlue *glue;
  MirLayouts *layouts;
  cl *cl;
  cl_func *funcs;     /* per MIR function */
  cl_func *externs;   /* per extern; UINT32_MAX id until first used */
  bool *extern_made;
  /* The runtime functions the lowering calls itself (fault posts, `msrt_free`), declared on first use. */
  struct ClNamed {
    const char *name;
    cl_func func;
  } named[24];
  uint32_t nnamed;
  cl_data *syms;          /* per data symbol of `data` */
  struct ClRuntimeData {     /* the runtime's data symbols the static data and code name, declared on first use */
    MsSpan name;
    cl_data data;
  } *runtime;
  uint32_t nruntime, cap_runtime;
  const uint32_t *scope_base; /* per function: module-wide index of its first scope */
  uint32_t total_scopes;
} ClModule;

/* The fault functions the lowering itself calls; each takes the listed number of i64 arguments. */
typedef enum ClPost {
  CLX_POST_INT_OVERFLOW, CLX_POST_INT_RANGE, CLX_POST_DIV_ZERO, CLX_POST_REM_ZERO, CLX_POST_DIV_OVERFLOW,
  CLX_POST_INDEX, CLX_POST_UNWRAP_NONE, CLX_POST_FAULT_POSTED, CLX_POST_COUNT
} ClPost;

typedef struct ClCx {
  ClModule *mod;
  const MirModule *module;
  const MirFunc *func;
  uint32_t index;          /* the function's id */
  MirLayouts *layouts;
  cl_fn *fb;
  const char *why;         /* the reason an instruction cannot be lowered; static text */
  cl_val *regs;         /* the leaves of every value, one after another; see `first` */
  uint32_t *first;         /* per value: index of its first leaf in `regs` */
  cl_block *blocks;     /* per MIR block */
  cl_block cur;         /* the Cranelift block instructions go to: a check continues in a new one */
  cl_val result_area;   /* the hidden result pointer, when the function has one */
  bool has_result_area;
  bool places;             /* tag each instruction with its source line for the fault tables */
  uint32_t scope_base;     /* module-wide index of the first scope of `func` */
  uint32_t body_scope;     /* the scope number of `func`'s own body */
  /* The stack areas calls share: a copy slot per argument position, and one result area, each made on first use. */
  cl_slot shared[CLX_SHARED_ARGS], area;
  uint32_t shared_bytes[CLX_SHARED_ARGS], area_bytes;
  bool shared_made[CLX_SHARED_ARGS], area_made;
  const bool *framed;      /* per value: a closure object kept in the frame */
  const bool *borrowed;    /* per value: an `iface.borrow` kept in the frame */
  uint32_t cur_block, cur_index; /* the MIR instruction being lowered; index == insts.len for the terminator */
} ClCx;

/* ---- leaves (cl_leaf.c) ---- */

MsSpan clx_leaves(ClCx *cx, MirTy type);
MsSpan clx_value_leaves(ClCx *cx, MirValue value);
MirTy clx_value_type(const ClCx *cx, MirValue value);
/* The register type of a leaf, and of the single leaf of a one-leaf value. */
cl_type clx_reg_type(MirLeaf leaf);
cl_type clx_value_reg_type(ClCx *cx, MirValue value);
bool clx_is_indirect(ClCx *cx, MirTy type);
uint32_t clx_slot_bytes(ClCx *cx, MirTy type);
/* The Cranelift value of leaf `leaf` of `value`, and setting it. */
cl_val clx_get(const ClCx *cx, MirValue value, uint32_t leaf);
void clx_set(ClCx *cx, MirValue value, uint32_t leaf, cl_val reg);
/* The one value of a one-leaf operand. */
cl_val clx_arg(const ClCx *cx, const MirInst *inst, uint32_t arg);
/* The i64 constant `k`. */
cl_val clx_const(ClCx *cx, int64_t k);
/* Widens a loaded leaf to its register type and narrows a register for a store. */
cl_val clx_widen(ClCx *cx, MirLeaf leaf, cl_val loaded);

/* ---- memory (cl_mem.c) ---- */

/* Loads leaf `leaf` of `dst` from `base + offset`, and stores it. */
void clx_load_leaf(ClCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, cl_val base, int32_t offset);
void clx_store_leaf(ClCx *cx, MirLeaf leaf, MirValue src, uint32_t index, cl_val base, int32_t offset);
/* Reads (`load`) or writes the leaves of `value` at `base`. */
void clx_leaves_at(ClCx *cx, MirValue value, cl_val base, bool load);
/* A zeroed stack slot of `bytes` bytes: its address. */
cl_val clx_slot(ClCx *cx, uint32_t bytes);
/* The leaf `dst` leaf `to` takes leaf `from` of `src`, converting between leaf types when they differ. */
void clx_copy_leaf(ClCx *cx, MirValue dst, uint32_t to, MirValue src, uint32_t from);
void clx_zero_leaf(ClCx *cx, MirValue dst, uint32_t index, MirLeaf leaf);

/* ---- operations by family; each sets `*handled` and returns false only when `cx->why` is set ---- */

bool clx_scalar_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_checked_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_memory_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_call_op(ClCx *cx, const MirInst *inst, bool *handled);
/* Sizes the shared stack areas of the calls of the function; call once before lowering it. */
void clx_frame_areas(ClCx *cx);
/* The type a runtime function takes or returns a leaf in. */
cl_type clx_rt_leaf_type(MirLeaf leaf, bool is_c);

/* Ends the current block with a check: when `condition` (an i8) holds the program calls fault function `post` with the
 * i64 `args` and leaves by the exit of the instruction being lowered, or ends when it has none; otherwise it
 * continues in a new block. */
void clx_fault_if(ClCx *cx, cl_val condition, ClPost post, const cl_val *args, uint32_t nargs);

/* ---- one-sided branches (cl_branch.c) ---- */

#define CLX_IF_WORDS 8u
typedef struct ClIf {
  cl_block then, join;
  uint32_t words;
} ClIf;

/* Branches on the i8 `condition`: continues in the side that runs when it holds. `words` i64 values leave the side;
 * when it is skipped they are zero. */
ClIf clx_if_begin(ClCx *cx, cl_val condition, uint32_t words);
/* Ends the side with `values` (`words` of them) and continues in the join; `joined` receives its words. */
void clx_if_end(ClCx *cx, const ClIf *branch, const cl_val *values, cl_val *joined);

/* ---- records (cl_record.c) ---- */

bool clx_record_op(ClCx *cx, const MirInst *inst, bool *handled);
/* A heap block of `bytes` bytes from the runtime, as an address. */
cl_val clx_alloc(ClCx *cx, uint32_t bytes);

bool clx_option_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_list_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_closure_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_iface_op(ClCx *cx, const MirInst *inst, bool *handled);
bool clx_string_op(ClCx *cx, const MirInst *inst, bool *handled);

/* ---- static data (cl_data.c) ---- */

/* Declares and defines every data symbol of the module's MirData. */
void clx_define_data(ClModule *mod);
void clx_free_data(ClModule *mod);
bool clx_data_op(ClCx *cx, const MirInst *inst, bool *handled);
/* The address of what `ref` names, as a value. */
cl_val clx_ref_address(ClCx *cx, MirRef ref);

/* ---- fault tables (cl_tables.c) ---- */

/* Waits for the functions and defines `tables_data` as the fault tables of the module. */
bool clx_define_tables(ClModule *mod, const EmitTableInfo *info, cl_data tables_data, MsStrBuild *why);

/* ---- the module (cl_module.c) ---- */

/* A NUL-terminated copy of a name, in `text`. */
const char *clx_c_name(MsStrBuild *text, MsSpan name);

/* The Cranelift function of runtime function `external`, declared on first use. */
cl_func clx_extern_func(ClModule *mod, uint32_t external);
/* A runtime function the lowering calls by name: the module's own declaration when it lists one, else `nargs` i64
 * parameters and an i64 result when `has_result`. */
cl_func clx_runtime_func(ClModule *mod, const char *name, uint32_t nargs, bool has_result);
cl_func clx_post_func(ClModule *mod, ClPost post);

#endif
