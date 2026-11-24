/* depth: lowers `depth.enter`, the stack-depth check of a recursive function, to ordinary
 * operations. 
 *
 * The check runs first in the function: when the stack pointer is below the task's limit
 * (`stack.low`), the function runs again on a new stack segment. Its entry parameters are stored in
 * a heap block, `task.grow` calls the function's grow shim there with the block, and the function
 * returns what that run left in the block. The shim is a small function of its own that loads the
 * parameters, calls the function and stores the result. Backends see only `stack.low`, memory
 * operations and calls.
 *
 * Runs last, after `unwind`: the check must stay the first instruction of the entry block while the
 * other passes look for it. */

#include "compiler/mir/mir_depth.h"

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_pass.h"

typedef struct DpRuntime { uint32_t alloc, free, grow; } DpRuntime;

/* Where each entry parameter and the result sit in the block, and the block's size. */
typedef struct DpCells {
  int64_t *params;
  int64_t result, size;
} DpCells;

/* Appends instructions to a block of `f`; the instructions carry no location: the check is not
 * source code, and a position on its call would add a frame to the stack trace of an overflow. */
typedef struct DpEmit {
  MirModule *m;
  MirFunc *f;
  MirBlock block;
} DpEmit;

static MirValue dp_op(DpEmit *e, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
           bool has_result, MirTy ty) {
  const MirValue res = has_result ? mir_new_value(e->f, ty) : MIR_NONE;
  MirBlockData *blk = &e->f->blocks.ptr[e->block];
  const MirInst inst = mir_inst(op, imm, res, MIR_LOC_NONE, mir_args_copy(e->m, args, nargs), nargs);
  mir_inst_list_push(&blk->insts, inst);
  return res;
}

static MirValue dp_int(DpEmit *e, int64_t n) {
  return dp_op(e, MOP_IConst, NULL, 0, mir_imm_int(n), true, MIR_INT);
}

/* The address `off` bytes into `base`. */
static MirValue dp_at(DpEmit *e, MirValue base, int64_t off) {
  if (off == 0) {
    return base;
  }
  const MirValue pair[2] = {base, dp_int(e, off)};
  return dp_op(e, MOP_PtrAdd, pair, 2, mir_imm_none(), true, MIR_PTR);
}

static MirValue dp_call(DpEmit *e, uint32_t ext, const MirValue *args, uint32_t nargs, MirTy ret) {
  return dp_op(e, MOP_CallRt, args, nargs, mir_imm_ext(ext), true, ret);
}

static MirImm dp_imm_ty(MirTy ty) { return (MirImm){.tag = MI_TY, .a = ty}; }
static MirImm dp_imm_func(uint32_t g) { return (MirImm){.tag = MI_FUNC, .a = g}; }

static DpCells dp_cells(MirModule *m, const MirFunc *f) {
  MirLayouts lay;
  mir_layouts_init(&lay, m);
  DpCells c = {.params = MS_ARENA_NEW_ARRAY(&m->arena, int64_t, f->nparams ? f->nparams : 1)};
  int64_t off = 0;
  for (uint32_t i = 0; i <= f->nparams; i++) {
    const MirTy ty = i < f->nparams ? f->params[i].ty : f->ret;
    const MirMemLayout mem = mir_type_mem(&lay, ty);
    const int64_t align = mem.align;
    off = (off + align - 1) / align * align;
    if (i < f->nparams) {
      c.params[i] = off;
    } else {
      c.result = off;
    }
    off += mem.size;
  }
  c.size = (off + 7) / 8 * 8;
  mir_layouts_free(&lay);
  return c;
}

/* The shim: `fn(block)` loads the parameters, runs the function and stores its result. */
static uint32_t dp_shim(MirModule *m, uint32_t fi, const DpCells *cells) {
  const MirFunc *f = &m->funcs.ptr[fi];
  const MirParam ptr = {MIR_PTR, MM_BORROW};
  MirFunc shim;
  mir_func_init(m, &shim, mir_name_suffixed(m, f->name, ms_span_of_text(".grow")), &ptr, 1, MIR_VOID);
  shim.loc = f->loc;
  DpEmit e = {.m = m, .f = &shim, .block = 0};
  const MirValue block = shim.blocks.ptr[0].params.ptr[0].value;
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, f->nparams ? f->nparams : 1);
  for (uint32_t i = 0; i < f->nparams; i++) {
    const MirValue at = dp_at(&e, block, cells->params[i]);
    const MirOp op = f->params[i].mode == MM_BORROW ? MOP_Load : MOP_Take;
    args[i] = dp_op(&e, op, &at, 1, dp_imm_ty(f->params[i].ty), true, f->params[i].ty);
  }
  const MirValue result = dp_op(&e, MOP_Call, args, f->nparams, dp_imm_func(fi), true, f->ret);
  if (f->ret != MIR_VOID) {
    const MirValue put[2] = {dp_at(&e, block, cells->result), result};
    /* A borrowed result stays a borrow on both sides of the block. */
    dp_op(&e, f->ret_borrowed ? MOP_Store : MOP_Put, put, 2, mir_imm_none(), false, MIR_VOID);
  }
  const MirValue done = dp_op(&e, MOP_VoidConst, NULL, 0, mir_imm_none(), true, MIR_VOID);
  shim.blocks.ptr[0].term = (MirTerm){.kind = MT_RET, .value = done};
  shim.blocks.ptr[0].term_loc = MIR_LOC_NONE;
  return mir_add_func(m, &shim);
}

/* The grow path: allocate the block, store the parameters, run the shim on a new stack segment and
 * return what it left. */
static void dp_grow_path(DpEmit *e, const DpRuntime *rt, uint32_t shim_id, const DpCells *cells,
            const MirBlockParam *entry_params, MirBlock grow) {
  const MirFunc *f = e->f;
  const bool ret_borrowed = f->ret_borrowed;
  const MirTy ret = f->ret;
  const uint32_t nparams = f->nparams;
  e->block = grow;
  MirValue size = dp_int(e, cells->size > 8 ? cells->size : 8);
  const MirValue blk = dp_call(e, rt->alloc, &size, 1, MIR_PTR);
  for (uint32_t i = 0; i < nparams; i++) {
    const MirValue put[2] = {dp_at(e, blk, cells->params[i]), entry_params[i].value};
    dp_op(e, e->f->params[i].mode == MM_BORROW ? MOP_Store : MOP_Put, put, 2, mir_imm_none(),
       false, MIR_VOID);
  }
  const MirValue shim_addr = dp_op(e, MOP_FuncAddr, NULL, 0, dp_imm_func(shim_id), true, MIR_PTR);
  const MirValue call[2] = {shim_addr, blk};
  (void)dp_call(e, rt->grow, call, 2, MIR_VOID);
  MirValue out;
  if (ret == MIR_VOID) {
    out = dp_op(e, MOP_VoidConst, NULL, 0, mir_imm_none(), true, MIR_VOID);
  } else {
    const MirValue at = dp_at(e, blk, cells->result);
    out = dp_op(e, ret_borrowed ? MOP_Load : MOP_Take, &at, 1, dp_imm_ty(ret), true, ret);
  }
  (void)dp_call(e, rt->free, &blk, 1, MIR_VOID);
  e->f->blocks.ptr[grow].term = (MirTerm){.kind = MT_RET, .value = out};
  e->f->blocks.ptr[grow].term_loc = MIR_LOC_NONE;
}

/* Puts `depth.enter` first in `func`; false when it is already there. */
static bool dp_insert_enter(MirFunc *func) {
  MirBlockData *entry = &func->blocks.ptr[0];
  if (entry->insts.len > 0 && entry->insts.ptr[0].op == MOP_DepthEnter) {
    return false;
  }
  MirInstList out = {0};
  mir_inst_list_push(&out, mir_inst(MOP_DepthEnter, mir_imm_none(), MIR_NONE, MIR_LOC_NONE, NULL, 0));
  for (uint32_t i = 0; i < entry->insts.len; i++) {
    mir_inst_list_push(&out, entry->insts.ptr[i]);
  }
  mir_inst_list_free(&entry->insts);
  entry->insts = out;
  return true;
}

/* Frames above this many bytes (by the bound below, before elaboration) get the stack check. */
#define DP_LARGE_FRAME 8192

/* The bytes a value of `ty` takes in the frame of a call it crosses, or 0 when it passes in registers. */
static int64_t dp_by_address(MirLayouts *lay, MirTy ty) {
  const uint32_t size = mir_type_mem(lay, ty).size;
  return size > 16 ? (int64_t)size : 0;
}

/* A bound on the frame of `f` once compiled: its slots, and a word for every value, since the fast register
 * allocator spills each value that lives across a block. The check leaves this much room below the limit, so a frame
 * that does not fit grows a segment instead of running into the guard page. */
static int64_t dp_frame_bound(MirModule *m, const MirFunc *f) {
  MirLayouts lay;
  mir_layouts_init(&lay, m);
  int64_t bytes = 8 * (int64_t)f->values.len;
  for (size_t block = 0; block < f->blocks.len; block++) {
    const MirInstList *insts = &f->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      const MirInst *inst = &insts->ptr[index];
      if (inst->op == MOP_Slot) {
        bytes += (int64_t)mir_type_mem(&lay, inst->imm.a).size;
      } else if (inst->op == MOP_Call || inst->op == MOP_CallInd || inst->op == MOP_CallMethod || inst->op == MOP_CallRt) {
        /* A value of more than two words crosses a call by address: the emitter keeps a copy of each argument and an
         * area for the result in the frame. */
        for (uint32_t arg = 0; arg < inst->nargs; arg++) {
          bytes += dp_by_address(&lay, mir_value_ty(f, inst->args[arg]));
        }
        bytes += inst->res != MIR_NONE ? dp_by_address(&lay, mir_value_ty(f, inst->res)) : 0;
      }
    }
  }
  mir_layouts_free(&lay);
  return bytes;
}

/* The check, then the grow path out of line. */
static void dp_expand(MirModule *m, uint32_t fi, const DpRuntime *rt) {
  const DpCells cells = dp_cells(m, &m->funcs.ptr[fi]);
  const uint32_t shim_id = dp_shim(m, fi, &cells);
  MirFunc *f = &m->funcs.ptr[fi];
  MirBlockData entry = f->blocks.ptr[0];
  f->blocks.ptr[0] = mir_block_empty();
  const MirBlock grow = mir_new_block(f);
  const MirBlock cont = mir_new_block(f);
  MirBlockData *cb = &f->blocks.ptr[cont];
  for (uint32_t i = 1; i < entry.insts.len; i++) {
    mir_inst_list_push(&cb->insts, entry.insts.ptr[i]);
  }
  cb->term = entry.term;
  cb->term_loc = entry.term_loc;
  mir_inst_list_free(&entry.insts);
  f->blocks.ptr[0].params = entry.params;
  DpEmit e = {.m = m, .f = f, .block = 0};
  const MirValue low = dp_op(&e, MOP_StackNear, NULL, 0, mir_imm_int(dp_frame_bound(m, f)), true, MIR_BOOL);
  f->blocks.ptr[0].term = (MirTerm){.kind = MT_CONDBR, .value = low, .a = {.block = grow}, .b = {.block = cont}};
  f->blocks.ptr[0].term_loc = MIR_LOC_NONE;
  /* The rare path: the backends lay it out of line. */
  f->blocks.ptr[grow].cold = true;
  dp_grow_path(&e, rt, shim_id, &cells, entry.params.ptr, grow);
}

/* Frames above this many bytes (by the bound) put the check in a small function of its own: a frame that big, once
 * allocated, may already sit below the guard page, and the grow path could not run in it. The function keeps its place
 * and becomes the check; its body moves to `<name>.body`. */
#define DP_STUB_FRAME 16384

/* `f` becomes the check and the grow path; its code, minus `depth.enter`, is the new function `<name>.body` that the
 * check calls when the stack has room. */
static void dp_split(MirModule *m, uint32_t fi, const DpRuntime *rt) {
  const DpCells cells = dp_cells(m, &m->funcs.ptr[fi]);
  const int64_t bound = dp_frame_bound(m, &m->funcs.ptr[fi]);
  const uint32_t shim_id = dp_shim(m, fi, &cells);
  MirFunc body = m->funcs.ptr[fi];
  MirInstList *insts = &body.blocks.ptr[0].insts;
  for (uint32_t i = 1; i < insts->len; i++) {
    insts->ptr[i - 1] = insts->ptr[i];
  }
  insts->len--;
  body.name = mir_name_suffixed(m, body.name, ms_span_of_text(".body"));
  body.linkage = ML_INTERNAL;
  body.inline_hint = MINL_NEVER;
  const uint32_t body_id = mir_add_func(m, &body);
  MirFunc *f = &m->funcs.ptr[fi];
  MirFunc fresh;
  mir_func_init(m, &fresh, f->name, f->params, f->nparams, f->ret);
  f->blocks = fresh.blocks;
  f->values = fresh.values;
  f->names = fresh.names;
  f->scopes = fresh.scopes;
  f->exact = NULL;
  f->nexact = 0;
  f->noalias = NULL;
  f->nnoalias = 0;
  f->has_slot_result = f->has_close_exit = f->has_slot_close = false;
  f->raw_scratch = false;
  const MirBlock grow = mir_new_block(f);
  const MirBlock run = mir_new_block(f);
  const MirBlockParam *params = f->blocks.ptr[0].params.ptr;
  DpEmit e = {.m = m, .f = f, .block = 0};
  const MirValue low = dp_op(&e, MOP_StackNear, NULL, 0, mir_imm_int(bound), true, MIR_BOOL);
  f->blocks.ptr[0].term = (MirTerm){.kind = MT_CONDBR, .value = low, .a = {.block = grow}, .b = {.block = run}};
  f->blocks.ptr[0].term_loc = MIR_LOC_NONE;
  f->blocks.ptr[grow].cold = true;
  dp_grow_path(&e, rt, shim_id, &cells, params, grow);
  e.block = run;
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, f->nparams ? f->nparams : 1);
  for (uint32_t i = 0; i < f->nparams; i++) {
    args[i] = params[i].value;
  }
  MirValue result = dp_op(&e, MOP_Call, args, f->nparams, dp_imm_func(body_id), true, f->ret);
  if (f->ret == MIR_VOID) {
    result = dp_op(&e, MOP_VoidConst, NULL, 0, mir_imm_none(), true, MIR_VOID);
  }
  f->blocks.ptr[run].term = (MirTerm){.kind = MT_RET, .value = result};
  f->blocks.ptr[run].term_loc = MIR_LOC_NONE;
}

static uint32_t dp_extern(MirModule *m, const char *name, const MirTy *params, uint32_t n, MirTy ret,
                          bool fresh) {
  MirParam list[2];
  for (uint32_t i = 0; i < n; i++) {
    list[i] = (MirParam){params[i], MM_BORROW};
  }
  MirExtern def = {.name = mir_name(m, ms_span_of_text(name)), .params = list, .nparams = n, .ret = ret,
                   .fresh = fresh, .role = MR_NONE};
  return mir_extern_intern(m, &def);
}

bool mir_depth_lower(MirModule *m) {
  uint32_t ntodo = 0;
  uint32_t *todo = MS_ARENA_NEW_ARRAY(&m->arena, uint32_t, m->funcs.len ? m->funcs.len : 1);
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    /* A function with a large frame checks too, recursive or not: the check of the recursive function above it leaves
     * only the headroom, and a callee whose frame is larger would step over the guard page. */
    if (f->blocks.len > 0 && dp_frame_bound(m, f) > DP_LARGE_FRAME) {
      (void)dp_insert_enter(f);
    }
    if (f->blocks.len > 0 && f->blocks.ptr[0].insts.len > 0 && f->blocks.ptr[0].insts.ptr[0].op == MOP_DepthEnter) {
      todo[ntodo++] = fi;
    }
  }
  if (ntodo == 0) {
    return false;
  }
  const MirTy int_param = MIR_INT, ptr_param = MIR_PTR, two_ptrs[2] = {MIR_PTR, MIR_PTR};
  const DpRuntime rt = {
    .alloc = dp_extern(m, "msrt_alloc", &int_param, 1, MIR_PTR, true),
    .free = dp_extern(m, "msrt_free", &ptr_param, 1, MIR_VOID, false),
    .grow = dp_extern(m, "msrt_task_grow", two_ptrs, 2, MIR_VOID, false),
  };
  for (uint32_t k = 0; k < ntodo; k++) {
    if (m->funcs.ptr[todo[k]].kind == MFK_NORMAL && dp_frame_bound(m, &m->funcs.ptr[todo[k]]) > DP_STUB_FRAME) {
      dp_split(m, todo[k], &rt);
    } else {
      dp_expand(m, todo[k], &rt);
    }
  }
  return true;
}

/* ---- marking recursive functions ---- */

typedef struct DpGraph {
  const MirModule *m;
  uint32_t *index, *low, *stack, *frame_func, *frame_next;
  bool *on_stack, *recursive;
  uint32_t counter;
} DpGraph;

/* The next function `func` calls directly after the instruction at `*cursor` (a flat walk over its
 * blocks), or UINT32_MAX when there is none. */
static uint32_t dp_next_callee(const MirFunc *func, uint32_t *cursor) {
  uint32_t at = 0;
  for (uint32_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (uint32_t i = 0; i < insts->len; i++, at++) {
      const MirInst *inst = &insts->ptr[i];
      if (at >= *cursor && inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
        *cursor = at + 1;
        return inst->imm.a;
      }
    }
  }
  *cursor = at;
  return UINT32_MAX;
}

/* Whether the function runs code that can reach any function through a pointer: it then may recurse
 * through one. */
static bool dp_calls_indirectly(const MirFunc *func) {
  for (uint32_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (uint32_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_CallInd || insts->ptr[i].op == MOP_CallMethod) {
        return true;
      }
    }
  }
  return false;
}

/* Tarjan's strongly connected components over direct calls, without recursion of its own: a function in a
 * component of two or more, or calling itself, is recursive. */
static void dp_scc(DpGraph *g, uint32_t root) {
  uint32_t depth = 0, top = 0;
  g->frame_func[0] = root;
  g->frame_next[0] = 0;
  g->index[root] = g->low[root] = ++g->counter;
  g->stack[top++] = root;
  g->on_stack[root] = true;
  depth = 1;
  while (depth > 0) {
    const uint32_t f = g->frame_func[depth - 1];
    const uint32_t callee = dp_next_callee(&g->m->funcs.ptr[f], &g->frame_next[depth - 1]);
    if (callee != UINT32_MAX) {
      if (callee == f) {
        g->recursive[f] = true;
      }
      if (g->index[callee] == 0) {
        g->index[callee] = g->low[callee] = ++g->counter;
        g->stack[top++] = callee;
        g->on_stack[callee] = true;
        g->frame_func[depth] = callee;
        g->frame_next[depth] = 0;
        depth++;
      } else if (g->on_stack[callee] && g->index[callee] < g->low[f]) {
        g->low[f] = g->index[callee];
      }
      continue;
    }
    depth--;
    if (depth > 0) {
      const uint32_t parent = g->frame_func[depth - 1];
      g->low[parent] = g->low[f] < g->low[parent] ? g->low[f] : g->low[parent];
    }
    if (g->low[f] != g->index[f]) {
      continue;
    }
    uint32_t members = 0;
    for (uint32_t k = top; k > 0; k--) {
      members++;
      if (g->stack[k - 1] == f) {
        break;
      }
    }
    for (uint32_t k = 0; k < members; k++) {
      const uint32_t member = g->stack[--top];
      g->on_stack[member] = false;
      g->recursive[member] = g->recursive[member] || members > 1;
    }
  }
}

bool mir_depth_mark(MirModule *m) {
  const uint32_t count = (uint32_t)m->funcs.len;
  if (count == 0) {
    return false;
  }
  MsArena *arena = &m->arena;
  DpGraph g = {.m = m,
               .index = MS_ARENA_NEW_ARRAY(arena, uint32_t, count),
               .low = MS_ARENA_NEW_ARRAY(arena, uint32_t, count),
               .stack = MS_ARENA_NEW_ARRAY(arena, uint32_t, count),
               .frame_func = MS_ARENA_NEW_ARRAY(arena, uint32_t, count),
               .frame_next = MS_ARENA_NEW_ARRAY(arena, uint32_t, count),
               .on_stack = MS_ARENA_NEW_ARRAY(arena, bool, count),
               .recursive = MS_ARENA_NEW_ARRAY(arena, bool, count)};
  for (uint32_t f = 0; f < count; f++) {
    g.index[f] = g.low[f] = 0;
    g.on_stack[f] = g.recursive[f] = false;
  }
  for (uint32_t f = 0; f < count; f++) {
    if (g.index[f] == 0 && m->funcs.ptr[f].blocks.len > 0) {
      dp_scc(&g, f);
    }
  }
  /* The runtime calls a descriptor's equality and hash functions back, so a value that reaches itself recurses
   * through them without a direct call between them. */
  for (size_t k = 0; k < m->desc_glue.len; k++) {
    g.recursive[m->desc_glue.ptr[k].eq] = true;
    g.recursive[m->desc_glue.ptr[k].hash] = true;
  }
  bool changed = false;
  for (uint32_t f = 0; f < count; f++) {
    MirFunc *func = &m->funcs.ptr[f];
    if (func->blocks.len == 0 || !(g.recursive[f] || dp_calls_indirectly(func))) {
      continue;
    }
    changed = dp_insert_enter(func) || changed;
  }
  return changed;
}
