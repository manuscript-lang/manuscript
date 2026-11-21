/* compiler/mir/mir_elab_state.c: the move-state dataflow of drop elaboration: the state of the owners in
 * scope, its transfer function over one instruction, the join of two states, and the fixpoint. */
#include "base/sort.h"
#include "compiler/mir/mir_elab.h"

/* ---- states ---- */

ElSt el_part(ElCx *cx, uint32_t alt, uint32_t cs, uint32_t mask) {
  for (uint32_t index = 0; index < cx->nparts; index++) {
    const ElPart *part = &cx->parts[index];
    if (part->alt == alt && part->cs == cs && part->mask == mask) {
      return EL_PLAIN_KINDS + index;
    }
  }
  if (cx->nparts == cx->cparts) {
    const uint32_t cap = cx->cparts != 0 ? cx->cparts * 2 : 8;
    ElPart *grown = MS_ARENA_NEW_ARRAY(cx->ma, ElPart, cap);
    if (cx->nparts > 0) {
      __builtin_memcpy(grown, cx->parts, sizeof(ElPart) * cx->nparts);
    }
    cx->parts = grown;
    cx->cparts = cap;
  }
  cx->parts[cx->nparts] = (ElPart){alt, cs, mask};
  return EL_PLAIN_KINDS + cx->nparts++;
}

bool el_is_part(ElSt state) {
  return state >= EL_PLAIN_KINDS;
}

const ElPart *el_part_of(const ElCx *cx, ElSt state) {
  return &cx->parts[state - EL_PLAIN_KINDS];
}

bool el_is_odd(ElSt state) {
  return state == EL_MAYBE || state == EL_MAYBE_CLOSED || state == EL_CLOSED_OR_MOVED;
}

static uint64_t pack(MirValue value, ElSt kind) {
  return (uint64_t)value << 32 | kind;
}

void el_push(ElCx *cx, ElState *state, MirValue value, ElSt kind) {
  posmap_insert(cx->ma, &state->at, value, state->next);
  posmap_insert(cx->ma, &state->seq, state->next, pack(value, kind));
  state->next++;
  if (el_is_odd(kind)) {
    owner_insert(cx->ma, &state->odd, value);
  }
}

bool el_position_of(const ElState *state, MirValue value, uint32_t *position) {
  uint64_t found = 0;
  if (!posmap_get(&state->at, value, &found)) {
    return false;
  }
  *position = (uint32_t)found;
  return true;
}

bool el_get(const ElState *state, MirValue value, ElSt *kind) {
  uint32_t position = 0;
  uint64_t entry = 0;
  if (!el_position_of(state, value, &position) || !posmap_get(&state->seq, position, &entry)) {
    return false;
  }
  *kind = (ElSt)entry;
  return true;
}

void el_set(ElCx *cx, ElState *state, MirValue value, ElSt kind) {
  uint32_t position = 0;
  ElSt old = 0;
  if (!el_position_of(state, value, &position) || (el_get(state, value, &old) && old == kind)) {
    return;
  }
  posmap_insert(cx->ma, &state->seq, position, pack(value, kind));
  if (el_is_odd(kind)) {
    owner_insert(cx->ma, &state->odd, value);
  } else {
    (void)owner_remove(cx->ma, &state->odd, value);
  }
}

void el_remove(ElCx *cx, ElState *state, MirValue value) {
  uint32_t position = 0;
  if (!el_position_of(state, value, &position)) {
    return;
  }
  (void)posmap_remove(cx->ma, &state->at, value);
  (void)posmap_remove(cx->ma, &state->seq, position);
  (void)owner_remove(cx->ma, &state->odd, value);
}

ElOwner *el_owners(ElCx *cx, const ElState *state, uint32_t *count) {
  const uint64_t *entries = posmap_values(cx->ma, &state->seq);
  ElOwner *out = MS_ARENA_NEW_ARRAY(cx->ma, ElOwner, (size_t)state->seq.len + 1);
  for (uint32_t index = 0; index < state->seq.len; index++) {
    out[index] = (ElOwner){index, (MirValue)(entries[index] >> 32), (ElSt)entries[index]};
  }
  *count = state->seq.len;
  return out;
}

static int64_t by_position(uint8_t *env, const uint8_t *x, const uint8_t *y) {
  (void)env;
  ElOwner a, b;
  __builtin_memcpy(&a, x, sizeof a);
  __builtin_memcpy(&b, y, sizeof b);
  return (int64_t)a.pos - (int64_t)b.pos;
}

ElOwner *el_odd(ElCx *cx, const ElState *state, uint32_t *count) {
  uint32_t total = 0;
  const uint32_t *values = owner_to_vec(cx->ma, &state->odd, &total);
  ElOwner *out = MS_ARENA_NEW_ARRAY(cx->ma, ElOwner, (size_t)total + 1);
  uint32_t kept = 0;
  for (uint32_t index = 0; index < total; index++) {
    ElOwner owner = {0, values[index], 0};
    if (el_position_of(state, owner.v, &owner.pos) && el_get(state, owner.v, &owner.st)) {
      out[kept++] = owner;
    }
  }
  if (kept > 1) {
    ms_sort((uint8_t *)out, kept, sizeof *out, by_position, NULL);
  }
  *count = kept;
  return out;
}

/* Equal states are the common join: the shared trees say so without reading an entry. */
bool el_state_equal(const ElState *x, const ElState *y) {
  if (posmap_same_entries(&x->seq, &y->seq) && posmap_same_entries(&x->at, &y->at)) {
    return true;
  }
  if (x->seq.len != y->seq.len) {
    return false;
  }
  MsArena scratch = ms_arena_new();
  const uint64_t *first = posmap_values(&scratch, &x->seq);
  const uint64_t *second = posmap_values(&scratch, &y->seq);
  bool same = true;
  for (uint32_t index = 0; index < x->seq.len && same; index++) {
    same = first[index] == second[index];
  }
  ms_arena_free(&scratch);
  return same;
}

/* ---- tags ---- */

bool el_tagged(const ElCx *cx, MirValue value) {
  return value < cx->nvalues0 && cx->tag_scope[value] >= 0;
}

bool el_is_slot_owner(const ElCx *cx, MirValue value) {
  return mir_value_ty(cx->f, value) == MIR_PTR && el_tagged(cx, value) && cx->tag_kind[value] >= 2;
}

/* ---- transfer ---- */

/* The owner `value` left the scope's hands on this path. A slot owner or a disowned owner stays tracked as
 * moved: its cleanup entry or the exits after it still act on it. Any other owner needs nothing from here
 * on, so its entry goes: keeping one per moved temporary made every block's state grow with the function. */
static void finish_owner(ElCx *cx, ElState *state, MirValue value) {
  const bool tracked = (el_tagged(cx, value) && cx->tag_kind[value] >= 2) || mh_has(&cx->disown_moves, value);
  if (tracked) {
    el_set(cx, state, value, EL_MOVED);
  } else {
    el_remove(cx, state, value);
  }
}

bool el_consume_value(ElCx *cx, ElState *state, MirValue value) {
  ElSt kind = 0;
  if (!el_get(state, value, &kind)) {
    return true;
  }
  if (kind == EL_LIVE) {
    finish_owner(cx, state, value);
    return true;
  }
  if (kind == EL_MOVED) {
    /* Disowned, then consumed by the op that takes it. */
    return mh_has(&cx->disown_moves, value) || el_fail(cx, "%%%u is consumed after it was moved", value);
  }
  if (kind == EL_MAYBE || kind == EL_CLOSED_OR_MOVED) {
    return el_fail(cx, "%%%u is consumed but moved on some path", value);
  }
  if (el_is_part(kind)) {
    return el_fail(cx, "%%%u is consumed after a partial move", value);
  }
  return el_fail(cx, "%%%u is consumed after the program closed it", value);
}

static const char *kind_name(ElSt kind) {
  static const char *const names[] = {"Live", "Moved", "Maybe", "Closed", "MaybeClosed", "ClosedOrMoved"};
  return kind < EL_PLAIN_KINDS ? names[kind] : "Part";
}

static bool apply_disown(ElCx *cx, ElState *state, MirValue value) {
  ElSt kind = 0;
  if (el_is_slot_owner(cx, value)) {
    /* A memory slot owner whose value moved out stays tracked: its entry is cancelled and the scope end
     * closes nothing for it on this path. */
    if (!el_get(state, value, &kind) || kind == EL_MOVED) {
      return true;
    }
    if (kind == EL_LIVE || kind == EL_CLOSED) {
      el_set(cx, state, value, EL_MOVED);
      return true;
    }
    return el_fail(cx, "slot owner %%%u moved out of in an unsupported state %s", value, kind_name(kind));
  }
  /* A flagged owner stays tracked as moved: the op that consumes it after the disown, and the exits after
   * it, see the flag turn false. */
  if (mh_has(&cx->disown_moves, value) && el_get(state, value, &kind) && kind == EL_LIVE) {
    el_set(cx, state, value, EL_MOVED);
  } else {
    el_remove(cx, state, value);
  }
  return true;
}

static bool apply_mark(ElCx *cx, ElState *state, const MirInst *inst) {
  const MirValue value = inst->args[0];
  const bool refill = inst->imm.tag == MI_INT && inst->imm.i == 2;
  const ElSt next = inst->imm.tag == MI_INT && inst->imm.i == 1 ? EL_CLOSED : EL_LIVE;
  ElSt kind = 0;
  if (!el_get(state, value, &kind)) {
    return true;
  }
  if (kind == EL_LIVE || kind == EL_CLOSED || kind == EL_MAYBE_CLOSED) {
    el_set(cx, state, value, next);
    return true;
  }
  /* A refill stores a new value in a slot whose value moved out. */
  if (refill && (kind == EL_MOVED || kind == EL_MAYBE || kind == EL_CLOSED_OR_MOVED)) {
    el_set(cx, state, value, EL_LIVE);
    return true;
  }
  return el_fail(cx, "slot owner %%%u closed by hand after a move", value);
}

/* `alt.take` of a payload field out of an owner marks it partially moved. */
static bool apply_take(ElCx *cx, ElState *state, const MirInst *inst) {
  ElSt current = 0;
  if (inst->op != MOP_AltTake) {
    return true;
  }
  const MirValue value = inst->args[0];
  if (!el_get(state, value, &current) || !el_tagged(cx, value)) {
    return true;
  }
  const uint32_t alt = inst->imm.a, cs = inst->imm.b, bit = 1u << inst->imm.c;
  ElSt next = EL_MOVED;
  if (current == EL_LIVE) {
    next = el_part(cx, alt, cs, bit);
  } else if (el_is_part(current) && el_part_of(cx, current)->alt == alt && el_part_of(cx, current)->cs == cs) {
    next = el_part(cx, alt, cs, el_part_of(cx, current)->mask | bit);
  } else if (!(current == EL_MOVED && mh_has(&cx->disown_moves, value))) {
    /* (Disowned ahead of the take: the value already left the scope, so it stays moved.) */
    return el_fail(cx, "alt.take on %%%u in an unsupported state", value);
  }
  el_set(cx, state, value, next);
  return true;
}

static bool consume_args(ElCx *cx, ElState *state, const MirInst *inst) {
  MirMode *modes = MS_ARENA_NEW_ARRAY(cx->ma, MirMode, (size_t)inst->nargs + 1);
  mir_arg_modes(cx->m, cx->f, inst, modes);
  for (uint32_t index = 0; index < inst->nargs; index++) {
    const MirValue arg = inst->args[index];
    if (modes[index] == MM_MOVE && mir_needs_drop(cx->m, mir_value_ty(cx->f, arg)) &&
        !el_consume_value(cx, state, arg)) {
      return false;
    }
  }
  return true;
}

static bool apply_own(ElCx *cx, ElState *state, const MirInst *inst) {
  /* A disowned view that moves into another local is owned again by that local's scope; a slot owner handed
   * on to an enclosing scope holds its value again. */
  const MirValue value = inst->args[0];
  ElSt kind = 0;
  if (!el_get(state, value, &kind)) {
    el_push(cx, state, value, EL_LIVE);
  } else if (kind == EL_MOVED && el_is_slot_owner(cx, value)) {
    el_set(cx, state, value, EL_LIVE);
  }
  return true;
}

static void apply_scope_end(ElCx *cx, ElState *state, const MirInst *inst) {
  const uint32_t scope = inst->imm.a;
  if (scope >= cx->nscopes) {
    return;
  }
  for (size_t index = 0; index < cx->owners[scope].len; index++) {
    el_remove(cx, state, cx->owners[scope].ptr[index]);
  }
}

bool el_apply(ElCx *cx, ElState *state, const MirInst *inst) {
  ElSt kind = 0;
  switch ((MirOp)inst->op) {
  case MOP_ScopeDisown:
    return apply_disown(cx, state, inst->args[0]);
  case MOP_ScopeMark:
    return apply_mark(cx, state, inst);
  case MOP_ScopeOwn:
    return apply_own(cx, state, inst);
  case MOP_ScopeEnd:
    apply_scope_end(cx, state, inst);
    return true;
  default:
    break;
  }
  /* Lowering releases what an `alt.take` left behind itself: that finishes the owner. */
  if (inst->op == MOP_AltRelease && el_get(state, inst->args[0], &kind) && el_is_part(kind)) {
    finish_owner(cx, state, inst->args[0]);
    return true;
  }
  MirMode result = MM_BORROW;
  if (!consume_args(cx, state, inst) || !apply_take(cx, state, inst)) {
    return false;
  }
  if (mir_result_mode(cx->m, cx->f, inst, &result) && result == MM_MOVE && inst->res != MIR_NONE) {
    el_push(cx, state, inst->res, EL_LIVE);
  }
  return true;
}

/* ---- edges and joins ---- */

MirValue *el_own_params(const ElCx *cx, uint32_t block, uint32_t *count) {
  const MirBlockData *data = &cx->f->blocks.ptr[block];
  MirValue *list = MS_ARENA_NEW_ARRAY(cx->ma, MirValue, data->params.len + 1);
  uint32_t found = 0;
  for (size_t index = 0; index < data->params.len; index++) {
    const MirBlockParam *param = &data->params.ptr[index];
    if (param->mode == MM_MOVE && mir_needs_drop(cx->m, mir_value_ty(cx->f, param->value))) {
      list[found++] = param->value;
    }
  }
  *count = found;
  return list;
}

/* The state flowing along the edge `target`: the arguments of owning parameters are consumed. */
bool el_edge_state(ElCx *cx, const ElState *state, const MirTarget *target, ElState *out) {
  const MirBlockData *dest = &cx->f->blocks.ptr[target->block];
  *out = *state;
  const size_t count = target->nargs < dest->params.len ? target->nargs : dest->params.len;
  for (size_t index = 0; index < count; index++) {
    if (dest->params.ptr[index].mode == MM_MOVE &&
        mir_needs_drop(cx->m, mir_value_ty(cx->f, target->args[index])) &&
        !el_consume_value(cx, out, target->args[index])) {
      return false;
    }
  }
  return true;
}

static bool held_or_closed(ElSt kind) {
  return kind == EL_LIVE || kind == EL_CLOSED || kind == EL_MAYBE_CLOSED;
}

static bool hand_closed(ElSt kind) {
  return kind == EL_CLOSED || kind == EL_MAYBE_CLOSED || kind == EL_CLOSED_OR_MOVED;
}

/* The state of an owner both paths hold, or false when they cannot be joined. */
static bool join_one(ElCx *cx, MirValue value, ElSt a, ElSt b, ElSt *out) {
  if (a == b) {
    *out = a;
  } else if (held_or_closed(a) && held_or_closed(b)) {
    *out = EL_MAYBE_CLOSED;
  } else if (el_is_part(a) || el_is_part(b)) {
    return el_fail(cx, "%%%u is partially moved on only some paths", value);
  } else if (hand_closed(a) || hand_closed(b)) {
    *out = EL_CLOSED_OR_MOVED;
  } else {
    *out = EL_MAYBE;
  }
  return true;
}

bool el_merge(ElCx *cx, const ElState *old, const ElState *next, ElState *out) {
  if (el_state_equal(old, next)) {
    *out = *old;
    return true;
  }
  *out = (ElState){0};
  uint32_t count = 0;
  const ElOwner *mine = el_owners(cx, old, &count);
  for (uint32_t index = 0; index < count; index++) {
    ElSt other = EL_LIVE, joined = EL_LIVE;
    if (!el_get(next, mine[index].v, &other)) {
      /* Gone on the other path: consumed or disowned there, so moved. */
      if (mine[index].st == EL_LIVE || mine[index].st == EL_MAYBE) {
        el_push(cx, out, mine[index].v, EL_MAYBE);
      }
    } else if (join_one(cx, mine[index].v, mine[index].st, other, &joined)) {
      el_push(cx, out, mine[index].v, joined);
    } else {
      return false;
    }
  }
  const ElOwner *theirs = el_owners(cx, next, &count);
  for (uint32_t index = 0; index < count; index++) {
    ElSt seen = 0;
    if (!el_get(old, theirs[index].v, &seen) && (theirs[index].st == EL_LIVE || theirs[index].st == EL_MAYBE)) {
      el_push(cx, out, theirs[index].v, EL_MAYBE);
    }
  }
  return true;
}

/* ---- the fixpoint ---- */

/* The state at the end of block `block` from its entry state. */
static bool walk_block(ElCx *cx, uint32_t block, ElState *state) {
  uint32_t nparams = 0;
  const MirValue *params = el_own_params(cx, block, &nparams);
  for (uint32_t index = 0; index < nparams; index++) {
    el_push(cx, state, params[index], EL_LIVE);
  }
  const MirBlockData *data = &cx->f->blocks.ptr[block];
  for (size_t index = 0; index < data->insts.len; index++) {
    if (!el_apply(cx, state, &data->insts.ptr[index])) {
      return false;
    }
  }
  return data->term.kind != MT_RET || data->term.value == MIR_NONE || el_consume_value(cx, state, data->term.value);
}

/* Merges the state leaving `block` into each successor; sets `*changed` when one entry state changed. */
static bool flow_edges(ElCx *cx, uint32_t block, const ElState *state, ElState *entry, bool *has, bool *dirty,
                       bool *changed) {
  const MirTerm *term = &cx->f->blocks.ptr[block].term;
  for (uint32_t index = 0; index < mir_term_ntargets(term); index++) {
    const MirTarget *target = mir_term_target_const(term, index);
    ElState next = {0}, merged = {0};
    if (!el_edge_state(cx, state, target, &next)) {
      return false;
    }
    const bool seen = has[target->block];
    merged = next;
    if (seen && !el_merge(cx, &entry[target->block], &next, &merged)) {
      return false;
    }
    if (!seen || !el_state_equal(&entry[target->block], &merged)) {
      entry[target->block] = merged;
      has[target->block] = true;
      dirty[target->block] = true;
      *changed = true;
    }
  }
  return true;
}

bool el_analyze(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has) {
  const size_t nblocks = cx->f->blocks.len;
  bool *dirty = MS_ARENA_NEW_ARRAY(cx->ma, bool, nblocks + 1);
  __builtin_memset(has, 0, nblocks + 1);
  entry[0] = (ElState){0};
  has[0] = true;
  dirty[0] = true;
  /* A block's outgoing states depend only on its entry state, so a pass revisits just the blocks whose entry
   * changed since they were last walked. */
  for (uint64_t round = 0; round <= 4 * (uint64_t)nblocks + 4; round++) {
    bool changed = false;
    for (uint32_t k = 0; k < norder; k++) {
      const MirBlock block = order[k];
      if (!dirty[block]) {
        continue;
      }
      dirty[block] = false;
      ElState state = entry[block];
      if (has[block] && (!walk_block(cx, block, &state) || !flow_edges(cx, block, &state, entry, has, dirty, &changed))) {
        return false;
      }
    }
    if (!changed) {
      return true;
    }
  }
  return el_fail(cx, "the move state did not reach a fixpoint");
}
