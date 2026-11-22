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
  const MirValue low = dp_op(&e, MOP_StackLow, NULL, 0, mir_imm_none(), true, MIR_BOOL);
  f->blocks.ptr[0].term = (MirTerm){.kind = MT_CONDBR, .value = low, .a = {.block = grow}, .b = {.block = cont}};
  f->blocks.ptr[0].term_loc = MIR_LOC_NONE;
  /* The rare path: the backends lay it out of line. */
  f->blocks.ptr[grow].cold = true;
  dp_grow_path(&e, rt, shim_id, &cells, entry.params.ptr, grow);
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
    const MirFunc *f = &m->funcs.ptr[fi];
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
    dp_expand(m, todo[k], &rt);
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
  bool changed = false;
  for (uint32_t f = 0; f < count; f++) {
    MirFunc *func = &m->funcs.ptr[f];
    if (func->blocks.len == 0 || func->unwind_only || !(g.recursive[f] || dp_calls_indirectly(func))) {
      continue;
    }
    MirBlockData *entry = &func->blocks.ptr[0];
    if (entry->insts.len > 0 && entry->insts.ptr[0].op == MOP_DepthEnter) {
      continue;
    }
    MirInstList out = {0};
    mir_inst_list_push(&out, mir_inst(MOP_DepthEnter, mir_imm_none(), MIR_NONE, MIR_LOC_NONE, NULL, 0));
    for (uint32_t i = 0; i < entry->insts.len; i++) {
      mir_inst_list_push(&out, entry->insts.ptr[i]);
    }
    mir_inst_list_free(&entry->insts);
    entry->insts = out;
    changed = true;
  }
  return changed;
}
