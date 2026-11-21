/* unwind: lets a cancelled or faulted task release the values its frames own. Port of
 * crates/ms-mir/src/unwind.rs (deleted; the design comment at the top of that file is in git history).
 *
 * Cancellation and a guarded fault leave a task by a jump, so no `drop` after the park or fault
 * point runs. Around every instruction that can reach a cancellation point or fault the pass
 * registers one runtime cleanup per owned value that is live across it, and discards them when it
 * completes; a run of such instructions with the same live values shares one registration:
 *
 *     h = cleanup.push v, drop_if_unwinding;  ..;  call f(..);  call.rt msrt_cleanup_discard(h)
 *
 * Only programs that start tasks or workers are rewritten. */

#include "compiler/mir/mir_unwind.h"

#include "base/fatal.h"

/* Which functions can fault: a checked operation, an explicit fault, an indirect call or a
 * runtime call, directly or through a callee. A function that parks can also fault. */
static bool *uw_faulting_funcs(MsArena *a, const MirModule *m, const bool *parks) {
  const uint32_t n = m->funcs.len;
  bool *faults = MS_ARENA_NEW_ARRAY(a, bool, n ? n : 1);
  __builtin_memcpy(faults, parks, n);
  for (uint32_t i = 0; i < n; i++) {
    const MirFunc *f = &m->funcs.ptr[i];
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      faults[i] = faults[i] || f->blocks.ptr[b].term.kind == MT_FAULT;
    }
    UW_INSTS(f, b2, k, inst) {
      if (inst->op == MOP_Call) {
        continue;
      }
      if (inst->op == MOP_CallRt || inst->op == MOP_CallInd || inst->op == MOP_CallMethod ||
        (mir_op_info[inst->op].effects & MIR_E_FAULTS) != 0) {
        faults[i] = true;
      }
    }
  }
  for (bool changed = true; changed;) {
    changed = false;
    for (uint32_t i = 0; i < n; i++) {
      const MirFunc *f = &m->funcs.ptr[i];
      UW_INSTS(f, b, k, inst) {
        uint32_t g = 0;
        if (!faults[i] && uw_is_func(inst, MOP_Call, &g) && faults[g]) {
          faults[i] = true;
          changed = true;
        }
      }
    }
  }
  return faults;
}

/* The values of `f` that are raw slot copies: they own nothing, so an unwind frees their buffer
 * and leaves the elements to the list they were copied from. */
static void uw_raw_slots(UwCx *cx, const MirFunc *f) {
  cx->raw_values = (UwHash){0};
  UW_INSTS(f, b, i, inst) {
    const bool raw_call = inst->op == MOP_CallRt && inst->imm.tag == MI_EXT &&
               cx->m->externs.ptr[inst->imm.a].role == MR_RAW_SLOTS;
    if (((f->raw_scratch && inst->op == MOP_ListNew) || raw_call) && inst->res != MIR_NONE) {
      (void)uh_put(&cx->fn, &cx->raw_values, inst->res, 0);
    }
  }
}

/* The interface values `f` hands to a method call as its receiver and then forgets: the method
 * takes the payload out of the box, so a cancellation inside the call frees the box only. */
static void uw_moved_receivers(UwCx *cx, const MirFunc *f) {
  UwHash forgotten = {0};
  UW_INSTS(f, b, i, inst) {
    if (inst->op == MOP_Forget && inst->nargs > 0) {
      (void)uh_put(&cx->fn, &forgotten, inst->args[0], 0);
    }
  }
  cx->box_values = (UwHash){0};
  UW_INSTS(f, b, i, inst) {
    if (inst->op == MOP_CallMethod && inst->nargs > 0 && uh_has(&forgotten, inst->args[0])) {
      (void)uh_put(&cx->fn, &cx->box_values, inst->args[0], 0);
    }
  }
}

/* Rewrites the blocks that keep their registrations to a window of their own: each window opens
 * before its first instruction and discards what it holds after its last. */
static void uw_rewrite_windows(UwCx *cx, MirFunc *f, const UwWalk *walk, uint32_t bi,
               UwStacks *open_stacks, uint32_t *open_at) {
  MirInstList old_list = f->blocks.ptr[bi].insts;
  f->blocks.ptr[bi].insts = (MirInstList){0};
  const MirInst *old = old_list.ptr;
  const uint32_t len = (uint32_t)old_list.len;
  const MirLoc end_loc = len ? old[len - 1].loc : (MirLoc){0};
  const UwWindow *plan = walk->plans[bi];
  uint32_t next = 0, step = 0, nsteps = 0;
  const UwStep *steps = NULL;
  bool open_window = false;
  uint32_t window_last = 0;
  MirInstList out = {0};
  for (uint32_t k = 0; k < len; k++) {
    const MirLoc loc = old[k].loc;
    /* The recursion check stays first in its block: a registration before it would repeat
     * when the check re-invokes the function on a new stack segment. */
    const bool first = old[k].op == MOP_DepthEnter;
    if (first) {
      mir_inst_list_push(&out, old[k]);
    }
    if (next < walk->nplans[bi] && plan[next].first == k) {
      *open_at = UW_ROOT;
      uw_open_sync(cx, f, open_stacks, open_at, &out, &plan[next].values, loc);
      open_window = true;
      window_last = plan[next].last;
      steps = plan[next].steps;
      nsteps = plan[next].nsteps;
      step = 0;
      next++;
    }
    if (step < nsteps && steps[step].at == k) {
      uw_open_sync(cx, f, open_stacks, open_at, &out, &steps[step].target, loc);
      step++;
    }
    if (!first) {
      mir_inst_list_push(&out, old[k]);
    }
    MirInst close;
    if (open_window && window_last == k) {
      if (uw_open_close(cx, f, open_stacks, open_at, loc, &close)) {
        mir_inst_list_push(&out, close);
      }
      open_window = false;
    }
  }
  if (walk->nat_fault[bi] > 0) {
    /* No discard: the fault never returns, and its cleanups run LIFO. */
    MirValue *handles = MS_ARENA_NEW_ARRAY(&cx->fn, MirValue, walk->nat_fault[bi]);
    uw_push_each(cx, f, &out, walk->at_fault[bi], walk->nat_fault[bi], end_loc, handles);
  }
  mir_block_set_insts(&f->blocks.ptr[bi], &out);
  mir_inst_list_free(&old_list);
}

static bool uw_walk_idle(const UwWalk *w, uint32_t nblocks) {
  for (uint32_t b = 0; b < nblocks; b++) {
    if (w->nplans[b] > 0 || w->nat_fault[b] > 0) {
      return false;
    }
  }
  return true;
}

/* The values an existing cleanup entry (a scope close) uses: it must see them undropped. */
static UwHash uw_closed_by_with(UwCx *cx, const MirFunc *f) {
  UwHash set = {0};
  UW_INSTS(f, b, i, inst) {
    if (inst->op == MOP_CleanupPush && inst->nargs > 0) {
      (void)uh_put(&cx->fn, &set, inst->args[0], 0);
    }
  }
  return set;
}

static void uw_ice_flow(const MirFunc *f, const MirModule *m) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "internal compiler error: the cleanup flow of `");
  ms_strbuild_append(&text, ms_names_span(&m->names, f->name));
  ms_strbuild_append_text(&text, "` did not settle");
  ms_strbuild_append_byte(&text, 0);
  ms_fatal(MS_FATAL_INVARIANT, (const char *)ms_strbuild_span(&text).ptr);
}

/* The registrations of the function, once the loops are hoisted. */
static bool uw_register(UwCx *cx, MirFunc *f, const bool *def, uint32_t ndef,
            const UwHash *closed_by_with, UwHash *hoisted, bool other_changes) {
  const uint32_t *holes = uw_hole_states(cx, f);
  const UwFacts facts = {.cx = cx, .f = f, .owned_def = def, .nowned = ndef,
             .closed_by_with = closed_by_with, .holes = holes, .hoisted = hoisted};
  const UwWalk walk = uw_analyze(&facts);
  if (uw_walk_idle(&walk, f->blocks.len)) {
    return other_changes;
  }
  UwStacks flow_stacks, open_stacks;
  uws_init(&flow_stacks, &cx->fn);
  uws_init(&open_stacks, &cx->fn);
  UwFlow flow;
  if (!uw_plan_flow(cx, f, &walk, &flow_stacks, &flow)) {
    uw_ice_flow(f, cx->m);
  }
  UwHash handles = {0};
  uint32_t open_at = UW_ROOT;
  MirBlock *order = NULL;
  const uint32_t norder = mir_rpo(&cx->fn, f, &order);
  for (uint32_t oi = 0; oi < norder; oi++) {
    const uint32_t bi = order[oi];
    if (uw_flow_carries(&flow, bi)) {
      uw_rewrite_flow_block(cx, f, &walk, &flow, &flow_stacks, &handles, bi);
    } else if (walk.nplans[bi] > 0 || walk.nat_fault[bi] > 0) {
      uw_rewrite_windows(cx, f, &walk, bi, &open_stacks, &open_at);
    }
  }
  return true;
}

static bool uw_function(UwCx *cx, MirFunc *f, uint32_t fi) {
  if (f->blocks.len == 0) {
    return false;
  }
  bool *def = NULL;
  uint32_t ndef = 0;
  if (!uw_owned_values(cx, f, fi, &def, &ndef)) {
    return false;
  }
  uw_raw_slots(cx, f);
  uw_moved_receivers(cx, f);
  const UwHash in_slots = uw_covered_slot_takes(&cx->fn, cx->m, f, false);
  uw_name_holes(cx, f, &in_slots);
  const bool wrapped = uw_wrap_with_closers(cx, f);
  const bool shields = uw_cover_shielded_slots(cx, f);
  const bool closes = uw_cover_inline_closes(cx, f);
  uw_own_resize(cx, &def, &ndef, f->values.len);
  const UwHash closed_by_with = uw_closed_by_with(cx, f);
  UwHash *hoisted = NULL;
  const bool hoists = uw_hoist_loops(cx, f, &def, &ndef, &closed_by_with, &hoisted);
  return uw_register(cx, f, def, ndef, &closed_by_with, hoisted, wrapped || shields || closes || hoists);
}

/* The module's functions never change count while the pass runs through `count`; the closers it
 * adds are appended after them. */
static UwTable uw_pointer_params(MsArena *a, const MirModule *m) {
  UwTable t = {.v = MS_ARENA_NEW_ARRAY(a, bool *, m->funcs.len ? m->funcs.len : 1),
        .len = MS_ARENA_NEW_ARRAY(a, uint32_t, m->funcs.len ? m->funcs.len : 1), .n = m->funcs.len};
  for (uint32_t f = 0; f < m->funcs.len; f++) {
    t.len[f] = m->funcs.ptr[f].nparams;
    t.v[f] = MS_ARENA_NEW_ARRAY(a, bool, t.len[f] ? t.len[f] : 1);
    for (uint32_t k = 0; k < t.len[f]; k++) {
      t.v[f][k] = m->funcs.ptr[f].params[k].ty == MIR_PTR;
    }
  }
  return t;
}

/* An empty function with this one's signature. A pass that takes a function out of the module to
 * rewrite it leaves this behind, so a recursive call still reads which arguments the callee
 * consumes and whether its result borrows. */
static MirFunc uw_stand_in(MirModule *m, const MirFunc *f) { return mir_func_stand_in(m, f); }

bool mir_unwind(MirModule *m) {
  if (!mir_starts_tasks(m)) {
    return false;
  }
  UwCx cx = {.m = m, .nfuncs0 = m->funcs.len};
  cx.parks = mir_parking_funcs(&cx.pass, m);
  cx.faults = uw_faulting_funcs(&cx.pass, m, cx.parks);
  MirParam cleanup_param = {MIR_INT, MM_BORROW};
  const MirExtern discard = {.name = mir_name(m, ms_span_of_text("msrt_cleanup_discard")),
               .params = &cleanup_param, .nparams = 1, .ret = MIR_VOID,
               .leaf = true, .role = MR_CLEANUP_DISCARD};
  cx.discard = mir_extern_intern(m, &discard);
  cx.safe = uw_slot_safe_params(&cx.pass, m);
  cx.owns = uw_slot_owned_params(&cx.pass, m, &cx.safe);
  cx.pointer = uw_pointer_params(&cx.pass, m);
  cx.targets = uw_closure_targets(&cx.pass, m, &cx.ntargets);
  bool changed = false;
  const uint32_t count = m->funcs.len;
  for (uint32_t fi = 0; fi < count; fi++) {
    MirFunc f = m->funcs.ptr[fi];
    m->funcs.ptr[fi] = uw_stand_in(m, &f);
    changed = uw_function(&cx, &f, fi) || changed;
    m->funcs.ptr[fi] = f;
    ms_arena_free(&cx.fn);
  }
  ms_arena_free(&cx.pass);
  return changed;
}
