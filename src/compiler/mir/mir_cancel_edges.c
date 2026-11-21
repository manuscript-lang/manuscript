/* cancel_edges: makes a delivered cancel leave a task by ordinary returns.
 *
 * A park that is cancelled sets the task's `unwinding` byte and returns. After every call that can
 * park, this pass tests the byte and leaves the function through a cancel exit:
 *
 *     r = call f(..); u = call.rt msrt_unwinding(); c = ne u, 0; condbr c, x1, next
 *     x1: forget <every owned value live here>; br exit
 *     exit: call.rt msrt_cleanup_unwind_to(base); %z = undef; ret %z
 *
 * This first form is hybrid: the cleanups `unwind` registered still free the owners, run by
 * `msrt_cleanup_unwind_to` from the height taken at entry, so the owned values on the exit edge
 * are forgotten. The caller decides whether the pass runs at all (`MS_CANCEL_EDGES`). */

#include "compiler/mir/mir_cancel_edges.h"

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

typedef struct CeCx {
  MirModule *m;
  MirFunc *f;
  MsArena *scratch;
  const bool *parks;
  uint32_t unwinding, base, unwind_to;
  MirBlock exit;
} CeCx;

/* An instruction with a fresh result of type `ty`; returns the result. */
static MirValue ce_inst(CeCx *cx, MirInstList *buf, MirOp op, MirImm imm, MirTy ty, MirLoc loc,
            MirValue *args, uint32_t nargs) {
  MirValue res = mir_new_value(cx->f, ty);
  mir_inst_list_push(buf, mir_inst(op, imm, res, loc, mir_args_copy(cx->m, args, nargs), nargs));
  return res;
}

/* The cleanup height at entry goes first in the entry block; every cancel leaves through the one
 * exit block, which unwinds to that height and returns an undefined result. */
static void ce_make_exit(CeCx *cx) {
  MirFunc *f = cx->f;
  MirLoc loc = f->loc;
  MirInstList entry = {0};
  MirValue base = ce_inst(cx, &entry, MOP_CallRt, mir_imm_ext(cx->base), MIR_INT, loc, NULL, 0);
  cx->exit = mir_new_block(f);
  MirInstList exit = {0};
  ce_inst(cx, &exit, MOP_CallRt, mir_imm_ext(cx->unwind_to), MIR_VOID, loc, &base, 1);
  MirValue ret = MIR_NONE;
  if (f->ret != MIR_VOID) {
    /* A borrow-returning function hands back a borrowed zero (`undef 1`). */
    MirImm imm = f->ret_borrowed ? mir_imm_int(1) : mir_imm_none();
    ret = ce_inst(cx, &exit, MOP_Undef, imm, f->ret, loc, NULL, 0);
  }
  MirBlockData *eb = &f->blocks.ptr[cx->exit];
  mir_block_set_insts(eb, &exit);
  eb->term = (MirTerm){.kind = MT_RET, .value = ret};
  mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &entry.ptr[0]);
  mir_inst_list_free(&entry);
}

/* The state of the walk over one function: the owned values live at the start of each block (the
 * verifier makes the set the same on every edge into a block, so the first one found stands for
 * all of them). */
typedef struct CeFlow {
  MirBits *entry;
  bool *seen;
} CeFlow;

static bool ce_owned(const CeCx *cx, MirValue v) {
  return mir_needs_drop(cx->m, mir_value_ty(cx->f, v));
}

static void ce_add_move_params(const CeCx *cx, const MirBlockData *b, MirBits *live) {
  for (uint32_t i = 0; i < b->params.len; i++) {
    if (b->params.ptr[i].mode == MM_MOVE && ce_owned(cx, b->params.ptr[i].value)) {
      mir_bits_set(live, b->params.ptr[i].value);
    }
  }
}

/* Ends the block being built at a site: test the byte, branch to a leave block that forgets what
 * is live and goes to the exit, or on to a fresh block. Returns the fresh block. */
static MirBlock ce_split_site(CeCx *cx, MirBlock cur, MirInstList *buf, const MirBits *live,
               MirLoc loc, uint32_t nvalues) {
  MirValue u = ce_inst(cx, buf, MOP_CallRt, mir_imm_ext(cx->unwinding), MIR_UINT8, loc, NULL, 0);
  MirValue z = ce_inst(cx, buf, MOP_IConst, mir_imm_int(0), MIR_UINT8, loc, NULL, 0);
  MirValue pair[2] = {u, z};
  MirValue c = ce_inst(cx, buf, MOP_UICmp, mir_imm_cc(MCC_NE), MIR_BOOL, loc, pair, 2);
  MirBlock leave = mir_new_block(cx->f);
  MirBlock next = mir_new_block(cx->f);
  MirInstList forgets = {0};
  for (uint32_t v = 0; v < nvalues; v++) {
    if (mir_bits_test(live, v)) {
      mir_inst_list_push(&forgets, mir_inst(MOP_Forget, mir_imm_none(), MIR_NONE, loc,
                     mir_args_copy(cx->m, &v, 1), 1));
    }
  }
  MirBlockData *lb = &cx->f->blocks.ptr[leave];
  mir_block_set_insts(lb, &forgets);
  lb->term = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = {.block = cx->exit}};
  lb->term_loc = loc;
  MirBlockData *cb = &cx->f->blocks.ptr[cur];
  mir_block_set_insts(cb, buf);
  cb->term = (MirTerm){.kind = MT_CONDBR, .value = c, .a = {.block = leave},
            .b = {.block = next}};
  cb->term_loc = loc;
  return next;
}

/* Edges into other blocks: consumed arguments leave, and the set flows on. */
static void ce_flow_out(CeCx *cx, CeFlow *flow, const MirTerm *term, const MirBits *live) {
  MirBits out = mir_bits_new(cx->scratch, live->nbits);
  __builtin_memcpy(out.words, live->words, sizeof(uint64_t) * (((size_t)live->nbits + 63) / 64));
  if (term->kind == MT_RET && term->value != MIR_NONE) {
    mir_bits_clear(&out, term->value);
  }
  for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
    const MirTarget *t = mir_term_target_const(term, k);
    if (flow->seen[t->block]) {
      continue;
    }
    MirBits e = mir_bits_new(cx->scratch, live->nbits);
    __builtin_memcpy(e.words, out.words, sizeof(uint64_t) * (((size_t)live->nbits + 63) / 64));
    const MirBlockData *tb = &cx->f->blocks.ptr[t->block];
    for (uint32_t i = 0; i < t->nargs && i < tb->params.len; i++) {
      if (tb->params.ptr[i].mode == MM_MOVE) {
        mir_bits_clear(&e, t->args[i]);
      }
    }
    /* Parameters the target owns are added when it is visited. */
    flow->entry[t->block] = e;
    flow->seen[t->block] = true;
  }
}

/* Tracks ownership across `inst` and reports whether a cancel test follows it. */
static bool ce_step(CeCx *cx, MirBits *live, const MirInst *inst) {
  MirMode *modes = MS_ARENA_NEW_ARRAY(cx->scratch, MirMode, inst->nargs ? inst->nargs : 1);
  mir_arg_modes(cx->m, cx->f, inst, modes);
  for (uint32_t a = 0; a < inst->nargs; a++) {
    if (modes[a] == MM_MOVE) {
      mir_bits_clear(live, inst->args[a]);
    }
  }
  MirMode result = MM_BORROW;
  if (inst->res != MIR_NONE && mir_result_mode(cx->m, cx->f, inst, &result) &&
    result == MM_MOVE && ce_owned(cx, inst->res)) {
    mir_bits_set(live, inst->res);
  }
  return mir_inst_parks(cx->m, cx->parks, inst) && inst->op != MOP_Poll;
}

/* Rewrites block `bi`: after each site its instructions end in the cancel test. */
static void ce_block(CeCx *cx, CeFlow *flow, MirBlock bi, uint32_t nvalues) {
  MirBits live = mir_bits_new(cx->scratch, nvalues);
  __builtin_memcpy(live.words, flow->entry[bi].words, sizeof(uint64_t) * (((size_t)nvalues + 63) / 64));
  if (bi != 0) {
    ce_add_move_params(cx, &cx->f->blocks.ptr[bi], &live);
  }
  MirInstList old = cx->f->blocks.ptr[bi].insts;
  cx->f->blocks.ptr[bi].insts = (MirInstList){0};
  uint32_t count = (uint32_t)old.len;
  MirTerm term = cx->f->blocks.ptr[bi].term;
  MirLoc term_loc = cx->f->blocks.ptr[bi].term_loc;
  MirBlock cur = bi;
  MirInstList buf = {0};
  for (uint32_t k = 0; k < count; k++) {
    MirInst inst = old.ptr[k];
    bool site = ce_step(cx, &live, &inst);
    mir_inst_list_push(&buf, inst);
    if (site && !(k + 1 == count && term.kind == MT_UNREACHABLE)) {
      cur = ce_split_site(cx, cur, &buf, &live, inst.loc, nvalues);
    }
  }
  MirBlockData *cb = &cx->f->blocks.ptr[cur];
  mir_block_set_insts(cb, &buf);
  cb->term = term;
  cb->term_loc = term_loc;
  mir_inst_list_free(&old);
  ce_flow_out(cx, flow, &term, &live);
}

static bool ce_function(CeCx *cx) {
  MirFunc *f = cx->f;
  bool any = false;
  for (uint32_t b = 0; b < f->blocks.len && !any; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len && !any; i++) {
      any = mir_inst_parks(cx->m, cx->parks, &f->blocks.ptr[b].insts.ptr[i]);
    }
  }
  if (!any) {
    return false;
  }
  ce_make_exit(cx);
  uint32_t nvalues = f->values.len;
  uint32_t norig = f->blocks.len - 1; /* blocks made since are the cancel exits */
  MsArena scratch = ms_arena_new();
  cx->scratch = &scratch;
  CeFlow flow = {.entry = MS_ARENA_NEW_ARRAY(&scratch, MirBits, f->blocks.len),
         .seen = MS_ARENA_NEW_ARRAY(&scratch, bool, f->blocks.len)};
  MirBits first = mir_bits_new(&scratch, nvalues);
  ce_add_move_params(cx, &f->blocks.ptr[0], &first);
  flow.entry[0] = first;
  flow.seen[0] = true;
  MirBlock *order = NULL;
  uint32_t norder = mir_rpo(&scratch, f, &order);
  for (uint32_t i = 0; i < norder; i++) {
    if (order[i] < norig && flow.seen[order[i]]) {
      ce_block(cx, &flow, order[i], nvalues);
    }
  }
  cx->scratch = NULL;
  ms_arena_free(&scratch);
  return true;
}

/* The runtime's natives return with the flag set instead of jumping only once the program says
 * every function checks it: the entry says so first. */
static bool ce_announce(CeCx *cx, uint32_t on) {
  if (cx->m->entry == MIR_NONE || cx->m->funcs.ptr[cx->m->entry].blocks.len == 0) {
    return false;
  }
  MirFunc *f = &cx->m->funcs.ptr[cx->m->entry];
  MirValue res = mir_new_value(f, MIR_VOID);
  MirInst call = mir_inst(MOP_CallRt, mir_imm_ext(on), res, f->loc, mir_args_copy(cx->m, NULL, 0),
              0);
  mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &call);
  return true;
}

bool mir_cancel_edges(MirModule *m) {
  if (!mir_starts_tasks(m)) {
    return false;
  }
  MsArena arena = ms_arena_new();
  bool *parks = mir_parking_funcs(&arena, m);
  CeCx cx = {.m = m, .parks = parks};
  cx.unwinding = mir_extern_get(m, ms_span_of_text("msrt_unwinding"), NULL, 0, MIR_UINT8, true, MR_UNWINDING);
  cx.base = mir_extern_get(m, ms_span_of_text("msrt_cleanup_base"), NULL, 0, MIR_INT, true, MR_NONE);
  MirTy int_param = MIR_INT;
  cx.unwind_to = mir_extern_get(m, ms_span_of_text("msrt_cleanup_unwind_to"), &int_param, 1, MIR_VOID, false, MR_NONE);
  uint32_t on = mir_extern_get(m, ms_span_of_text("msrt_cancel_edges"), NULL, 0, MIR_VOID, true, MR_NONE);
  bool changed = ce_announce(&cx, on);
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    if (f->blocks.len == 0 || f->unwind_only || f->explicit_cancel) {
      continue;
    }
    cx.f = f;
    changed = ce_function(&cx) || changed;
  }
  ms_arena_free(&arena);
  return changed;
}
