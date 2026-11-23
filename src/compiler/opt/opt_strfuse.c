/* The `strfuse` pass: grows a string in place for `s = s + piece`.
 *
 * `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows with
 * no use of `s` in between, `string_append` takes `s` by move and grows it in place, so a loop
 * that builds a string stays linear even in an unoptimised build. A join whose first part is such
 * an `s` (`s += f"{k}={n};"`) takes `s` by move and becomes the role `MR_STRING_JOIN_GROW`, which `mir_expand` writes
 * out as growing `s` in place and copying the other parts after it. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

/* One call to rewrite, the drop of its grown string (the call's first argument), and whether the call is a join of
 * pieces rather than a concat of two strings. */
typedef struct FuseSite {
  MirBlock block;
  uint32_t call, drop;
  bool join;
} FuseSite;

/* Whether `inst` is a concat or join whose first argument is a string, and which. */
static bool twin_position(const MirModule *m, const MirFunc *f, const MirInst *inst, bool *join) {
  if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT || inst->nargs == 0 ||
      mir_value_ty(f, inst->args[0]) != MIR_STR) {
    return false;
  }
  const uint8_t role = m->externs.ptr[inst->imm.a].role;
  *join = role == MR_STRING_JOIN;
  return role == MR_STRING_CONCAT || *join;
}

static uint32_t count_uses(const MirInst *inst, MirValue v) {
  uint32_t n = 0;
  for (uint32_t k = 0; k < inst->nargs; k++) {
    n += inst->args[k] == v ? 1u : 0u;
  }
  return n;
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
      bool join = false;
      if (twin_position(m, f, inst, &join)) {
        const MirValue a = inst->args[0];
        const uint32_t j = next_index[a];
        if (mir_value_ty(f, a) == MIR_STR && mir_bits_test(&owned, a) &&
          count_uses(inst, a) == 1 && next_block[a] == b &&
          blk->insts.ptr[j].op == MOP_Drop) {
          sites[count++] = (FuseSite){b, i, j, join};
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

/* The growing twin of a call: `string_append` for a concat of two strings, a join that takes its first string. */
static uint32_t fuse_extern(MirModule *m, const MirFunc *f, const MirInst *inst, const FuseSite *s) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, inst->nargs);
  for (uint32_t k = 0; k < inst->nargs; k++) {
    params[k] = (MirParam){mir_value_ty(f, inst->args[k]), k == 0 ? MM_MOVE : MM_BORROW};
  }
  MirExtern def = {0};
  def.name = mir_name(m, ms_span_of_text(s->join ? "msrt_string_join_grow" : "msrt_string_append"));
  def.params = params;
  def.nparams = inst->nargs;
  def.ret = MIR_STR;
  def.fresh = true;
  def.leaf = true;
  def.role = s->join ? MR_STRING_JOIN_GROW : MR_STRING_APPEND;
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
