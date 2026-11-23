/* compiler/mir/mir_slot_scope.c: where each stack slot of a function is live.
 *
 * A `slot` whose address (and the addresses derived from it by offsets and selects) is only loaded through,
 * stored through and passed to calls that do not keep it holds nothing outside the instructions between its
 * creation and the last use of any of those addresses. The backends may give two such slots with disjoint
 * ranges the same storage. Any other slot (its address stored, returned, passed to a block, kept by the
 * runtime, or a view result pointing into it) keeps its place for the whole function. */
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

typedef enum Access { ACCESS_READ, ACCESS_WRITE, ACCESS_DERIVE, ACCESS_ESCAPE } Access;

/* Whether a runtime call keeps the address of an argument beyond the call. */
bool mir_extern_pins_argument(const MirExtern *external) {
  return external->retains || external->role == MR_BORROWS_ARGUMENT || external->role == MR_VIEW_RESULT;
}

/* How an instruction touches the slot behind its operand `arg`. */
static Access access_of(const MirModule *module, const MirInst *inst, uint32_t arg) {
  switch ((MirOp)inst->op) {
  case MOP_Load: case MOP_Take: case MOP_PtrLoadU: case MOP_BytesPush:
    return arg == 0 ? ACCESS_READ : ACCESS_ESCAPE;
  case MOP_Store: case MOP_Put: case MOP_PtrStoreU:
    return arg == 0 ? ACCESS_WRITE : ACCESS_ESCAPE;
  case MOP_PtrField: case MOP_PtrAdd:
    return arg == 0 ? ACCESS_DERIVE : ACCESS_ESCAPE;
  case MOP_Call: case MOP_CallInd: case MOP_CallMethod:
    return ACCESS_WRITE;
  case MOP_CallRt:
    return inst->imm.tag == MI_EXT && !mir_extern_pins_argument(&module->externs.ptr[inst->imm.a]) ? ACCESS_WRITE
                                                                                        : ACCESS_ESCAPE;
  default:
    return ACCESS_ESCAPE;
  }
}


typedef struct Scan {
  uint32_t *owner;  /* by value: the slot an address derives from, or MIR_NONE */
  bool *bad;        /* by slot value: the slot may not share storage */
} Scan;

static void term_use(void *context, MirValue value) {
  const Scan *scan = context;
  if (scan->owner[value] != MIR_NONE) {
    scan->bad[scan->owner[value]] = true;
  }
}

/* Marks each slot instruction as its own owner; false when there is none. */
static bool find_slots(const MirFunc *func, uint32_t *owner) {
  bool any = false;
  for (size_t value = 0; value < func->values.len; value++) {
    owner[value] = MIR_NONE;
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      if (insts->ptr[index].op == MOP_Slot && insts->ptr[index].res != MIR_NONE) {
        owner[insts->ptr[index].res] = insts->ptr[index].res;
        any = true;
      }
    }
  }
  return any;
}

/* Every address derived from a slot (an offset, or a select that may pick it) maps to it; the derivation
 * repeats until nothing is new, since blocks need not be in dominance order. A select between two slots
 * makes both unshareable. */
static void derive_owners(const MirModule *module, const MirFunc *func, Scan *scan) {
  uint32_t *owner = scan->owner;
  for (bool grew = true; grew;) {
    grew = false;
    for (size_t block = 0; block < func->blocks.len; block++) {
      const MirInstList *insts = &func->blocks.ptr[block].insts;
      for (size_t index = 0; index < insts->len; index++) {
        const MirInst *inst = &insts->ptr[index];
        if (inst->res == MIR_NONE || inst->nargs == 0 || owner[inst->res] != MIR_NONE) {
          continue;
        }
        if ((MirOp)inst->op == MOP_Select && inst->nargs == 3) {
          const uint32_t first = owner[inst->args[1]];
          const uint32_t second = owner[inst->args[2]];
          if (first == MIR_NONE && second == MIR_NONE) {
            continue;
          }
          if (first != MIR_NONE && second != MIR_NONE && first != second) {
            scan->bad[first] = scan->bad[second] = true;
          }
          owner[inst->res] = first != MIR_NONE ? first : second;
          grew = true;
        } else if (owner[inst->args[0]] != MIR_NONE && access_of(module, inst, 0) == ACCESS_DERIVE) {
          owner[inst->res] = owner[inst->args[0]];
          grew = true;
        }
      }
    }
  }
}

/* Marks the slots an instruction hands on or keeps. */
static void scan_inst(const MirModule *module, const Scan *scan, const MirInst *inst) {
  const bool select = (MirOp)inst->op == MOP_Select && inst->nargs == 3;
  for (uint32_t index = 0; index < inst->nargs; index++) {
    const uint32_t slot = scan->owner[inst->args[index]];
    if (slot == MIR_NONE) {
      continue;
    }
    if (select && index > 0) {
      continue; /* the result is an address of the slot as well, and is scanned itself */
    }
    Access how = access_of(module, inst, index);
    if ((how == ACCESS_DERIVE && index > 0) || how == ACCESS_ESCAPE) {
      scan->bad[slot] = true;
    }
  }
}

/* Slot numbers are dense (`ordinal`), so the liveness sets are small bit rows. */
typedef struct Live {
  uint32_t words;      /* words per row */
  uint64_t *in, *out;  /* by block */
  uint64_t *gen, *kill;
} Live;

static uint64_t *row(uint64_t *rows, const Live *live, size_t block) {
  return rows + block * live->words;
}

static void set_bit(uint64_t *bits, uint32_t number) {
  bits[number / 64] |= (uint64_t)1 << (number % 64);
}

static bool has_bit(const uint64_t *bits, uint32_t number) {
  return (bits[number / 64] >> (number % 64) & 1) != 0;
}

typedef struct Ranges {
  uint32_t *lo, *hi; /* by slot value */
} Ranges;

static void touch(const Ranges *ranges, uint32_t slot, uint32_t position) {
  ranges->lo[slot] = position < ranges->lo[slot] ? position : ranges->lo[slot];
  ranges->hi[slot] = position > ranges->hi[slot] ? position : ranges->hi[slot];
}

/* The largest set of slots the liveness rows may span; a bigger function keeps one alloca per slot. */
#define MAX_LIVE_WORDS ((size_t)1 << 22)

bool mir_slot_ranges(MsArena *arena, const MirModule *module, const MirFunc *func, uint32_t **lo_out,
                     uint32_t **hi_out, uint32_t *length) {
  const size_t count = func->values.len + 1;
  uint32_t *owner = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  if (!find_slots(func, owner)) {
    return false;
  }
  bool *bad = MS_ARENA_NEW_ARRAY(arena, bool, count);
  for (size_t value = 0; value < count; value++) {
    bad[value] = false;
  }
  Scan scan = {owner, bad};
  derive_owners(module, func, &scan);
  uint32_t *ordinal = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  uint32_t nslots = 0;
  for (size_t value = 0; value < func->values.len; value++) {
    ordinal[value] = owner[value] == value ? nslots++ : MIR_NONE;
  }
  uint32_t *base = MS_ARENA_NEW_ARRAY(arena, uint32_t, func->blocks.len + 1);
  uint32_t total = 0;
  for (size_t block = 0; block < func->blocks.len; block++) {
    base[block] = total;
    total += (uint32_t)func->blocks.ptr[block].insts.len + 1;
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t index = 0; index < data->insts.len; index++) {
      scan_inst(module, &scan, &data->insts.ptr[index]);
    }
    mir_term_each_value(&data->term, term_use, &scan);
  }
  base[func->blocks.len] = total;
  Live live = {.words = (nslots + 63) / 64};
  if (live.words * func->blocks.len > MAX_LIVE_WORDS) {
    return false;
  }
  const size_t cells = live.words * func->blocks.len + 1;
  live.in = MS_ARENA_NEW_ARRAY(arena, uint64_t, cells);
  live.out = MS_ARENA_NEW_ARRAY(arena, uint64_t, cells);
  live.gen = MS_ARENA_NEW_ARRAY(arena, uint64_t, cells);
  live.kill = MS_ARENA_NEW_ARRAY(arena, uint64_t, cells);
  for (size_t cell = 0; cell < cells; cell++) {
    live.in[cell] = live.out[cell] = live.gen[cell] = live.kill[cell] = 0;
  }
  uint32_t *lo = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  uint32_t *hi = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  Ranges ranges = {lo, hi};
  for (size_t value = 0; value < count; value++) {
    lo[value] = UINT32_MAX;
    hi[value] = 0;
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    uint64_t *gen = row(live.gen, &live, block);
    uint64_t *kill = row(live.kill, &live, block);
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      const MirInst *inst = &insts->ptr[index];
      const uint32_t position = base[block] + (uint32_t)index;
      if (inst->op == MOP_Slot && inst->res != MIR_NONE) {
        set_bit(kill, ordinal[inst->res]);
        touch(&ranges, inst->res, position);
        continue;
      }
      for (uint32_t arg = 0; arg < inst->nargs; arg++) {
        const uint32_t slot = owner[inst->args[arg]];
        if (slot == MIR_NONE) {
          continue;
        }
        touch(&ranges, slot, position);
        if (!has_bit(kill, ordinal[slot])) {
          set_bit(gen, ordinal[slot]);
        }
      }
    }
  }
  /* Slot addresses are SSA values, so a slot is live from its creation through the last use of an address
   * derived from it, around loops included. */
  for (bool changed = true; changed;) {
    changed = false;
    for (size_t block = func->blocks.len; block-- > 0;) {
      MirTerm *term = (MirTerm *)&func->blocks.ptr[block].term;
      uint64_t *out = row(live.out, &live, block);
      for (uint32_t target = 0; target < mir_term_ntargets(term); target++) {
        const uint64_t *next = row(live.in, &live, mir_term_target(term, target)->block);
        for (uint32_t word = 0; word < live.words; word++) {
          out[word] |= next[word];
        }
      }
      uint64_t *in = row(live.in, &live, block);
      const uint64_t *gen = row(live.gen, &live, block);
      const uint64_t *kill = row(live.kill, &live, block);
      for (uint32_t word = 0; word < live.words; word++) {
        const uint64_t updated = gen[word] | (out[word] & ~kill[word]);
        changed = changed || updated != in[word];
        in[word] = updated;
      }
    }
  }
  for (size_t value = 0; value < func->values.len; value++) {
    if (owner[value] != value) {
      continue;
    }
    if (bad[value]) {
      lo[value] = 0;
      hi[value] = UINT32_MAX;
      continue;
    }
    for (size_t block = 0; block < func->blocks.len; block++) {
      if (has_bit(row(live.in, &live, block), ordinal[value])) {
        touch(&ranges, (uint32_t)value, base[block]);
      }
      if (has_bit(row(live.out, &live, block), ordinal[value])) {
        touch(&ranges, (uint32_t)value, base[block + 1] - 1);
      }
    }
  }
  *lo_out = lo;
  *hi_out = hi;
  *length = total;
  return true;
}
