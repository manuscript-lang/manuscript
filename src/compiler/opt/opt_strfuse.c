/* The `strfuse` pass: grows a string in place for `s = s + piece`.
 *
 * `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows with
 * no use of `s` in between, `string_append` takes `s` by move and grows it in place, so a loop
 * that builds a string stays linear even in an unoptimised build. A join whose first part is such
 * an `s` (`s += f"{k}={n};"`) takes `s` by move and becomes the role `MR_STRING_JOIN_GROW`, which `mir_expand` writes
 * out as growing `s` in place and copying the other parts after it. Bytes follow the same rule: a concat whose
 * left side dies becomes `msrt_bytes_concat_grow`. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

/* One call to rewrite, the drop of its grown string or bytes (the call's first argument), and whether the call is a
 * join of pieces rather than a concat of two strings or two byte buffers. */
typedef struct FuseSite {
  MirBlock block;
  uint32_t call, drop;
  bool join, bytes;
} FuseSite;

/* Whether `inst` is a concat or join whose first argument is a string, or a bytes concat, and which. */
static bool twin_position(const MirModule *m, const MirFunc *f, const MirInst *inst, bool *join, bool *bytes) {
  if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT || inst->nargs == 0) {
    return false;
  }
  const MirTy first = mir_value_ty(f, inst->args[0]);
  const uint8_t role = m->externs.ptr[inst->imm.a].role;
  *bytes = first == MIR_BYTES && role == MR_BYTES_CONCAT;
  if (*bytes) {
    return true;
  }
  *join = first == MIR_STR && role == MR_STRING_JOIN;
  return first == MIR_STR && (role == MR_STRING_CONCAT || *join);
}

static uint32_t count_uses(const MirInst *inst, MirValue v) {
  uint32_t n = 0;
  for (uint32_t k = 0; k < inst->nargs; k++) {
    n += inst->args[k] == v ? 1u : 0u;
  }
  return n;
}

static bool mentions(const MirInst *inst, MirValue v) {
  return count_uses(inst, v) > 0;
}

/* Whether `inst` reads, writes or hands out the slot `s` other than by loading it. */
static bool disturbs(const MirInst *inst, MirValue s) {
  return inst->op != MOP_Load && mentions(inst, s);
}

static bool blocks_disturb(const MirBlockData *blk, uint32_t from, uint32_t to, MirValue s) {
  for (uint32_t i = from; i < to && i < blk->insts.len; i++) {
    if (disturbs(&blk->insts.ptr[i], s)) {
      return true;
    }
  }
  return false;
}

/* Whether the slot `s` is left alone on every path from the instruction at `load_at` in block `from` to the one at
 * `call_at` in block `to` (not passing through the load again): the blocks that are reachable from `from` and reach
 * `to` hold no use of `s` but loads, and neither does the rest of `from` or the start of `to`. A path that runs through
 * `to` before arriving there would run the slot update too, so such a `to` is refused. */
static bool slot_untouched(MsArena *arena, const MirFunc *f, MirBlock from, uint32_t load_at, MirBlock to,
                           uint32_t call_at, MirValue s) {
  const uint32_t n = (uint32_t)f->blocks.len;
  bool *forward = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)n + 1);
  bool *backward = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)n + 1);
  uint32_t *work = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)n + 1);
  uint32_t top = 0;
  for (uint32_t pass = 0; pass < 2; pass++) {
    bool *seen = pass == 0 ? forward : backward;
    top = 0;
    work[top++] = pass == 0 ? from : to;
    seen[work[0]] = true;
    while (top > 0) {
      const uint32_t b = work[--top];
      for (uint32_t c = 0; c < n; c++) {
        bool edge = false;
        const MirTerm *term = &f->blocks.ptr[pass == 0 ? b : c].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
          edge |= mir_term_target_const(term, t)->block == (pass == 0 ? c : b);
        }
        if (edge && !seen[c] && c != from) {
          seen[c] = true;
          work[top++] = c;
        }
      }
    }
  }
  for (uint32_t b = 0; b < n; b++) {
    if (b == from || b == to || !forward[b] || !backward[b]) {
      continue;
    }
    if (blocks_disturb(&f->blocks.ptr[b], 0, (uint32_t)f->blocks.ptr[b].insts.len, s)) {
      return false;
    }
  }
  /* `to` reached again from itself (a loop that skips the load) would run its slot update first. */
  const MirTerm *own = &f->blocks.ptr[to].term;
  for (uint32_t t = 0; t < mir_term_ntargets(own); t++) {
    const uint32_t next = mir_term_target_const(own, t)->block;
    if (next != from && forward[next] && backward[next]) {
      return false;
    }
  }
  return !blocks_disturb(&f->blocks.ptr[from], load_at + 1, (uint32_t)f->blocks.ptr[from].insts.len, s) &&
         !blocks_disturb(&f->blocks.ptr[to], 0, call_at, s);
}

/* One slot update `s = s + piece` in block `b`, rewritten so the string it replaces is owned when the concat runs:
 *
 *     a = load str S; ...; r = concat(a, piece); drops; y = take str S; drop y; put S, r
 *  => ...; y = take str S; r = concat(y, piece); drops; drop y; put S, r
 *
 * which is the shape the fusion below grows in place. A variable that lives in a slot (because a call may fault
 * while it is live) otherwise copies the whole string on every append, so a loop that builds a string is quadratic.
 * The load may be in an earlier block than the concat (the piece came out of an inlined call); the slot must be
 * left alone on every path between them. The drops between the call and the old `take` only release other values.
 * False when no site is left in the block. */
static bool lift_slot_take(MirModule *m, MirFunc *f, MirBlock b, const uint32_t *uses, MsArena *arena) {
  MirBlockData *blk = &f->blocks.ptr[b];
  for (uint32_t j = 0; j < blk->insts.len; j++) {
    bool join = false, bytes = false;
    if (!twin_position(m, f, &blk->insts.ptr[j], &join, &bytes) || bytes) {
      continue;
    }
    const MirValue a = blk->insts.ptr[j].args[0];
    if (uses[a] != 1) {
      continue;
    }
    uint32_t lb = MIR_NONE, li = 0;
    for (uint32_t x = 0; x < f->blocks.len && lb == MIR_NONE; x++) {
      for (uint32_t y = 0; y < f->blocks.ptr[x].insts.len; y++) {
        const MirInst *def = &f->blocks.ptr[x].insts.ptr[y];
        if (def->res == a) {
                      lb = def->op == MOP_Load && def->nargs == 1 && mir_value_ty(f, a) == MIR_STR ? x : MIR_NONE;
          li = y;
          break;
        }
      }
    }
    if (lb == MIR_NONE || (lb == b && li >= j)) {
      continue;
    }
    const MirValue slot = f->blocks.ptr[lb].insts.ptr[li].args[0];
    if (mentions(&blk->insts.ptr[j], slot)) {
      continue;
    }
    if (lb == b) {
      bool clear = true;
      for (uint32_t x = li + 1; x < j; x++) {
        clear &= !mentions(&blk->insts.ptr[x], a) && !mentions(&blk->insts.ptr[x], slot);
      }
      if (!clear) {
        continue;
      }
    } else if (!slot_untouched(arena, f, lb, li, b, j, slot)) {
      continue;
    }
    uint32_t k = j + 1;
    while (k < blk->insts.len && blk->insts.ptr[k].op == MOP_Drop) {
      k++;
    }
    if (k + 1 >= blk->insts.len || blk->insts.ptr[k].op != MOP_Take || blk->insts.ptr[k].nargs != 1 ||
        blk->insts.ptr[k].args[0] != slot || blk->insts.ptr[k + 1].op != MOP_Drop ||
        blk->insts.ptr[k + 1].args[0] != blk->insts.ptr[k].res) {
      continue;
    }
    const MirInst take = blk->insts.ptr[k];
    MirInst *out = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)blk->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t x = 0; x < blk->insts.len; x++) {
      if (x == k || (lb == b && x == li)) {
        continue;
      }
      if (x == j) {
        out[n++] = take;
        out[n] = blk->insts.ptr[x];
        out[n++].args[0] = take.res;
        continue;
      }
      out[n++] = blk->insts.ptr[x];
    }
    opt_block_set_insts(blk, out, n);
    if (lb != b) {
      MirBlockData *from = &f->blocks.ptr[lb];
      MirInst *kept = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)from->insts.len + 1);
      uint32_t count = 0;
      for (uint32_t x = 0; x < from->insts.len; x++) {
        if (x != li) {
          kept[count++] = from->insts.ptr[x];
        }
      }
      opt_block_set_insts(from, kept, count);
    }
    return true;
  }
  return false;
}

static bool lift_slot_takes(MirModule *m, MirFunc *f) {
  bool changed = false;
  MsArena arena = ms_arena_new();
  const uint32_t *uses = mir_use_counts(&arena, f);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    while (lift_slot_take(m, f, b, uses, &arena)) {
      /* A lift changes the counts of the two values it joins: count again, once per lift rather than per block. */
      changed = true;
      uses = mir_use_counts(&arena, f);
    }
  }
  ms_arena_free(&arena);
  return changed;
}

static uint32_t find_fuse_sites(MsArena *arena, const MirModule *m, const MirFunc *f, FuseSite **out) {
  const MirBits owned = mir_owned_values(arena, m, f, false);
  uint32_t *next_block = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len + 1);
  uint32_t *next_index = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len + 1);
  for (uint32_t v = 0; v < f->values.len; v++) {
    next_block[v] = MIR_NONE;
    next_index[v] = 0;
  }
  uint32_t count = 0;
  FuseSite *sites = MS_ARENA_NEW_ARRAY(arena, FuseSite, mir_inst_count(f) + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = (uint32_t)blk->insts.len; i-- > 0;) {
      const MirInst *inst = &blk->insts.ptr[i];
      bool join = false, bytes = false;
      if (twin_position(m, f, inst, &join, &bytes)) {
        const MirValue a = inst->args[0];
        const uint32_t j = next_index[a];
        if (mir_bits_test(&owned, a) &&
          count_uses(inst, a) == 1 && next_block[a] == b &&
          blk->insts.ptr[j].op == MOP_Drop) {
          sites[count++] = (FuseSite){b, i, j, join, bytes};
        }
      }
      for (uint32_t k = 0; k < inst->nargs; k++) {
        next_block[inst->args[k]] = b;
        next_index[inst->args[k]] = i;
      }
    }
  }
  *out = sites;
  return count;
}

/* The growing twin of a call: `string_append` for a concat of two strings, `bytes_concat_grow` for two byte buffers,
 * a join that takes its first string. */
static uint32_t fuse_extern(MirModule *m, const MirFunc *f, const MirInst *inst, const FuseSite *s) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, inst->nargs);
  for (uint32_t k = 0; k < inst->nargs; k++) {
    params[k] = (MirParam){mir_value_ty(f, inst->args[k]), k == 0 ? MM_MOVE : MM_BORROW};
  }
  MirExtern def = {0};
  const char *name = s->bytes ? "msrt_bytes_concat_grow" : s->join ? "msrt_string_join_grow" : "msrt_string_append";
  def.name = mir_name(m, ms_span_of_text(name));
  def.params = params;
  def.nparams = inst->nargs;
  def.ret = s->bytes ? MIR_BYTES : MIR_STR;
  def.fresh = true;
  def.leaf = true;
  def.role = s->bytes ? MR_BYTES_CONCAT_GROW : s->join ? MR_STRING_JOIN_GROW : MR_STRING_APPEND;
  return mir_extern_intern(m, &def);
}

/* Removes the drops of the strings the rewritten calls now take. */
static void remove_drops(MirModule *m, MirFunc *f, MsArena *arena, const FuseSite *sites, uint32_t count) {
  uint32_t *start = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->blocks.len + 1);
  uint32_t total = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    start[b] = total;
    total += (uint32_t)f->blocks.ptr[b].insts.len;
  }
  bool *removed = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)total + 1);
  for (uint32_t i = 0; i < total; i++) {
    removed[i] = false;
  }
  for (uint32_t s = 0; s < count; s++) {
    removed[start[sites[s].block] + sites[s].drop] = true;
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockData *blk = &f->blocks.ptr[b];
    MirInst *out = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)blk->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t k = 0; k < blk->insts.len; k++) {
      if (!removed[start[b] + k]) {
        out[n++] = blk->insts.ptr[k];
      }
    }
    if (n != blk->insts.len) {
      opt_block_set_insts(blk, out, n);
    }
  }
}

bool opt_strfuse(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    changed |= lift_slot_takes(m, f);
    MsArena arena = ms_arena_new();
    FuseSite *sites = NULL;
    const uint32_t count = find_fuse_sites(&arena, m, f, &sites);
    for (uint32_t s = 0; s < count; s++) {
      MirInst *call = &f->blocks.ptr[sites[s].block].insts.ptr[sites[s].call];
      call->imm.a = fuse_extern(m, f, call, &sites[s]);
    }
    if (count > 0) {
      remove_drops(m, f, &arena, sites, count);
      changed = true;
    }
    ms_arena_free(&arena);
  }
  return changed;
}
