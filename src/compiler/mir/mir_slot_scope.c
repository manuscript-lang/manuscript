/* compiler/mir/mir_slot_scope.c: where each stack slot, and each value kept in a stack cell, of a function is live.
 *
 * A value the caller asks for (a record held in memory instead of in registers) is live from its definition, or
 * from the end of each block that passes it to a block parameter, through its last use.
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
  case MOP_MemCopy: /* (destination, source, length): the bytes are read or written where the instruction is */
    return arg == 0 ? ACCESS_WRITE : ACCESS_READ;
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
  uint32_t *owner;     /* by value: the slot an address derives from, or the value itself, or MIR_NONE */
  bool *bad;           /* by slot value: the slot may not share storage */
  bool *wide;          /* by slot value: an instruction other than a plain load, store or copy touches it */
  const bool *values;  /* by value: kept in a cell, not a slot; NULL for none */
} Scan;

static bool is_cell_value(const Scan *scan, uint32_t object) {
  return scan->values != NULL && scan->values[object];
}

static void term_use(void *context, MirValue value) {
  const Scan *scan = context;
  if (scan->owner[value] != MIR_NONE && !is_cell_value(scan, scan->owner[value])) {
    scan->bad[scan->owner[value]] = true;
  }
}

/* Marks each slot instruction and each wanted value as its own owner; false when there is none. */
static bool find_slots(const MirFunc *func, const bool *values, uint32_t *owner) {
  bool any = false;
  for (size_t value = 0; value < func->values.len; value++) {
    owner[value] = values != NULL && values[value] ? (uint32_t)value : MIR_NONE;
    any = any || owner[value] != MIR_NONE;
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      /* `str.data` of an inline string points into a 16-byte frame slot of its own, which lives as long as the address. */
      if ((insts->ptr[index].op == MOP_Slot || insts->ptr[index].op == MOP_StrData) && insts->ptr[index].res != MIR_NONE) {
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
    if (slot == MIR_NONE || is_cell_value(scan, slot)) {
      continue;
    }
    if (select && index > 0) {
      continue; /* the result is an address of the slot as well, and is scanned itself */
    }
    Access how = access_of(module, inst, index);
    switch ((MirOp)inst->op) {
    case MOP_Load: case MOP_Take: case MOP_Store: case MOP_Put: case MOP_PtrField: case MOP_MemCopy: break;
    default: scan->wide[slot] = true; /* a call or an indexed access keeps it in memory */
    }
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

/* The largest number of words the liveness and conflict rows may take; a bigger function keeps one alloca per
 * slot. */
#define MAX_LIVE_WORDS ((size_t)1 << 22)

/* Everything the walks over a function need. */
typedef struct Walk {
  const MirFunc *func;
  const uint32_t *owner;
  const uint32_t *ordinal;
  const Live *live;
  uint32_t words;
  uint64_t *conflict; /* a row per object: the objects live at a point where it is made */
  MirCellDeath *deaths; /* NULL unless the caller wants them: room for every operand of the function */
  uint32_t ndeaths;
} Walk;

static uint64_t *conflict_row(const Walk *walk, uint32_t object) {
  return walk->conflict + (size_t)object * walk->words;
}

static void add_conflict(const Walk *walk, uint32_t a, uint32_t b) {
  if (a != b) {
    set_bit(conflict_row(walk, a), b);
    set_bit(conflict_row(walk, b), a);
  }
}

/* `object` shares no storage with anything in `set`. */
static void conflict_with(const Walk *walk, uint32_t object, const uint64_t *set) {
  for (uint32_t word = 0; word < walk->words; word++) {
    for (uint64_t bits = set[word]; bits != 0; bits &= bits - 1) {
      add_conflict(walk, object, word * 64 + (uint32_t)__builtin_ctzll(bits));
    }
  }
}

typedef struct TermLive {
  const Walk *walk;
  uint64_t *set;
} TermLive;

static void term_live(void *context, MirValue value) {
  TermLive *use = context;
  const uint32_t owner = use->walk->owner[value];
  if (owner != MIR_NONE) {
    set_bit(use->set, use->walk->ordinal[owner]);
  }
}

/* A block parameter is made where each predecessor ends: it conflicts with what is live into the block, the values
 * the edge hands over (its sources are read as it is written) and the block's other parameters. */
static void walk_edges(const Walk *walk, uint32_t block, uint64_t *scratch) {
  const MirBlockData *data = &walk->func->blocks.ptr[block];
  for (uint32_t target = 0; target < mir_term_ntargets(&data->term); target++) {
    const MirTarget *edge = mir_term_target_const(&data->term, target);
    const MirBlockData *next = &walk->func->blocks.ptr[edge->block];
    for (uint32_t word = 0; word < walk->words; word++) {
      scratch[word] = row(walk->live->in, walk->live, edge->block)[word];
    }
    for (uint32_t param = 0; param < next->params.len; param++) {
      const MirValue value = next->params.ptr[param].value;
      if (walk->owner[value] == value) {
        set_bit(scratch, walk->ordinal[value]);
      }
    }
    for (uint32_t param = 0; param < next->params.len; param++) {
      const MirValue value = next->params.ptr[param].value;
      if (walk->owner[value] != value) {
        continue;
      }
      const uint32_t object = walk->ordinal[value];
      conflict_with(walk, object, scratch);
      /* It is written as the other arguments are read; its own argument may sit where it will. */
      for (uint32_t arg = 0; arg < edge->nargs; arg++) {
        const uint32_t owner = walk->owner[edge->args[arg]];
        if (owner != MIR_NONE && arg != param) {
          add_conflict(walk, object, walk->ordinal[owner]);
        }
      }
    }
  }
}

/* Walks the block backwards from what is live at its end, so each object made there conflicts with everything live
 * where it is made, including the operands of the instruction that makes it. */
static void walk_block(Walk *walk, uint32_t block, uint64_t *set) {
  const MirBlockData *data = &walk->func->blocks.ptr[block];
  for (uint32_t word = 0; word < walk->words; word++) {
    set[word] = row(walk->live->out, walk->live, block)[word];
  }
  TermLive term = {walk, set};
  mir_term_each_value(&data->term, term_live, &term);
  for (size_t index = data->insts.len; index-- > 0;) {
    const MirInst *inst = &data->insts.ptr[index];
    if (inst->res != MIR_NONE && walk->owner[inst->res] == inst->res) {
      const uint32_t object = walk->ordinal[inst->res];
      conflict_with(walk, object, set);
      /* A callee writes its result while it reads its arguments; any other operation reads what it needs before it
       * writes, so a value may take the place of the one it replaces. */
      const bool call = inst->op == MOP_Call || inst->op == MOP_CallInd || inst->op == MOP_CallMethod ||
                        inst->op == MOP_CallRt;
      for (uint32_t arg = 0; call && arg < inst->nargs; arg++) {
        const uint32_t owner = walk->owner[inst->args[arg]];
        if (owner != MIR_NONE) {
          add_conflict(walk, object, walk->ordinal[owner]);
        }
      }
      set[object / 64] &= ~((uint64_t)1 << (object % 64));
    }
    for (uint32_t arg = 0; arg < inst->nargs; arg++) {
      const uint32_t owner = walk->owner[inst->args[arg]];
      if (owner != MIR_NONE) {
        if (walk->deaths != NULL && !has_bit(set, walk->ordinal[owner])) {
          walk->deaths[walk->ndeaths++] = (MirCellDeath){block, (uint32_t)index, walk->ordinal[owner]};
        }
        set_bit(set, walk->ordinal[owner]);
      }
    }
  }
  for (uint32_t param = 0; param < data->params.len; param++) {
    const MirValue value = data->params.ptr[param].value;
    if (walk->owner[value] == value) {
      conflict_with(walk, walk->ordinal[value], set);
    }
  }
}

bool mir_cell_conflicts(MsArena *arena, const MirModule *module, const MirFunc *func, const bool *values,
                        bool want_deaths, MirCellMap *map) {
  const size_t count = func->values.len + 1;
  uint32_t *owner = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  if (!find_slots(func, values, owner)) {
    return false;
  }
  bool *bad = MS_ARENA_NEW_ARRAY(arena, bool, count);
  for (size_t value = 0; value < count; value++) {
    bad[value] = false;
  }
  bool *wide = MS_ARENA_NEW_ARRAY(arena, bool, count);
  for (size_t value = 0; value < count; value++) {
    wide[value] = false;
  }
  Scan scan = {owner, bad, wide, values};
  derive_owners(module, func, &scan);
  uint32_t *ordinal = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  uint32_t *object_value = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  uint32_t nobjects = 0;
  for (size_t value = 0; value < func->values.len; value++) {
    ordinal[value] = MIR_NONE;
    if (owner[value] == value) {
      ordinal[value] = nobjects;
      object_value[nobjects++] = (uint32_t)value;
    }
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      scan_inst(module, &scan, inst);
    }
    mir_term_each_value(&data->term, term_use, &scan);
  }
  Live live = {.words = (nobjects + 63) / 64};
  if ((live.words + 1) * (func->blocks.len + nobjects + 1) > MAX_LIVE_WORDS) {
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
  for (size_t block = 0; block < func->blocks.len; block++) {
    uint64_t *gen = row(live.gen, &live, block);
    uint64_t *kill = row(live.kill, &live, block);
    const MirBlockData *data = &func->blocks.ptr[block];
    /* A block parameter is made where each predecessor ends, and is not live before the block. */
    for (uint32_t param = 0; param < data->params.len; param++) {
      const MirValue value = data->params.ptr[param].value;
      if (owner[value] == value) {
        set_bit(kill, ordinal[value]);
      }
    }
    for (size_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      for (uint32_t arg = 0; arg < inst->nargs; arg++) {
        const uint32_t object = owner[inst->args[arg]];
        if (object != MIR_NONE && !has_bit(kill, ordinal[object])) {
          set_bit(gen, ordinal[object]);
        }
      }
      if (inst->res != MIR_NONE && owner[inst->res] == inst->res) {
        set_bit(kill, ordinal[inst->res]);
      }
    }
    uint64_t *term_set = MS_ARENA_NEW_ARRAY(arena, uint64_t, live.words + 1);
    for (uint32_t word = 0; word < live.words; word++) {
      term_set[word] = 0;
    }
    Walk shallow = {func, owner, ordinal, &live, live.words, NULL, NULL, 0};
    TermLive collect = {&shallow, term_set};
    mir_term_each_value(&data->term, term_live, &collect);
    for (uint32_t word = 0; word < live.words; word++) {
      gen[word] |= term_set[word] & ~kill[word];
    }
  }
  /* Slot addresses and held values are SSA values, so each is live from its definition through its last use,
   * around loops included. */
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
  uint64_t *rows = MS_ARENA_NEW_ARRAY(arena, uint64_t, (size_t)nobjects * live.words + 1);
  for (size_t word = 0; word < (size_t)nobjects * live.words + 1; word++) {
    rows[word] = 0;
  }
  uint32_t operands = 0;
  for (uint32_t block = 0; want_deaths && block < func->blocks.len; block++) {
    for (size_t index = 0; index < func->blocks.ptr[block].insts.len; index++) {
      operands += func->blocks.ptr[block].insts.ptr[index].nargs;
    }
  }
  MirCellDeath *deaths = want_deaths ? MS_ARENA_NEW_ARRAY(arena, MirCellDeath, (size_t)operands + 1) : NULL;
  Walk walk = {func, owner, ordinal, &live, live.words, rows, deaths, 0};
  uint64_t *set = MS_ARENA_NEW_ARRAY(arena, uint64_t, live.words + 1);
  uint64_t *scratch = MS_ARENA_NEW_ARRAY(arena, uint64_t, live.words + 1);
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    walk_block(&walk, block, set);
    walk_edges(&walk, block, scratch);
  }
  bool *keep = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)nobjects + 1);
  for (uint32_t object = 0; object < nobjects; object++) {
    keep[object] = !bad[object_value[object]];
  }
  bool *promotable = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)nobjects + 1);
  for (uint32_t object = 0; object < nobjects; object++) {
    const uint32_t value = object_value[object];
    promotable[object] = !wide[value] && !bad[value] && !is_cell_value(&scan, value);
  }
  *map = (MirCellMap){.nobjects = nobjects, .words = live.words, .value = object_value, .ordinal = ordinal,
                      .conflict = rows, .shareable = keep, .promotable = promotable, .deaths = deaths,
                      .ndeaths = walk.ndeaths};
  return true;
}
