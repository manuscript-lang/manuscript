/* compiler/mir/mir_slot_scope.c: which stack slots of a function live in one block only.
 *
 * A `slot` whose address is formed, offset, loaded through, stored through and passed to calls inside one
 * block, and whose first access there writes it, holds nothing before that block's first access and nothing
 * after its terminator. The backends may give such a slot's storage to another block's temporary. Any other
 * slot (its address stored, returned, passed to a block, kept by the runtime, a view result pointing into it,
 * or used in several blocks) keeps its place for the whole function. */
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

typedef enum Access { ACCESS_READ, ACCESS_WRITE, ACCESS_DERIVE, ACCESS_ESCAPE } Access;

/* Whether a runtime call keeps the address of an argument beyond the call. */
static bool pins_argument(const MirExtern *external) {
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
    return inst->imm.tag == MI_EXT && !pins_argument(&module->externs.ptr[inst->imm.a]) ? ACCESS_WRITE
                                                                                        : ACCESS_ESCAPE;
  default:
    return ACCESS_ESCAPE;
  }
}

typedef struct SlotState {
  MirBlock block; /* MIR_NONE until the first access */
  bool confined, written;
} SlotState;

typedef struct Scan {
  const uint32_t *owner; /* by value: the slot an address derives from, or MIR_NONE */
  SlotState *seen;       /* by slot value */
} Scan;

static void term_use(void *context, MirValue value) {
  const Scan *scan = context;
  if (scan->owner[value] != MIR_NONE && scan->seen[scan->owner[value]].block != MIR_NONE) {
    scan->seen[scan->owner[value]].confined = false;
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

/* Every address derived from a slot maps to it; the derivation repeats until nothing is new, since blocks
 * need not be in dominance order. */
static void derive_owners(const MirModule *module, const MirFunc *func, uint32_t *owner) {
  for (bool grew = true; grew;) {
    grew = false;
    for (size_t block = 0; block < func->blocks.len; block++) {
      const MirInstList *insts = &func->blocks.ptr[block].insts;
      for (size_t index = 0; index < insts->len; index++) {
        const MirInst *inst = &insts->ptr[index];
        if (inst->res == MIR_NONE || inst->nargs == 0 || owner[inst->args[0]] == MIR_NONE ||
            owner[inst->res] != MIR_NONE || access_of(module, inst, 0) != ACCESS_DERIVE) {
          continue;
        }
        owner[inst->res] = owner[inst->args[0]];
        grew = true;
      }
    }
  }
}

static void scan_inst(const MirModule *module, const Scan *scan, const MirInst *inst, MirBlock here) {
  for (uint32_t index = 0; index < inst->nargs; index++) {
    const uint32_t slot = scan->owner[inst->args[index]];
    if (slot == MIR_NONE) {
      continue;
    }
    Access how = access_of(module, inst, index);
    if (how == ACCESS_DERIVE && index > 0) {
      how = ACCESS_ESCAPE; /* an address in the value position of an operation is kept or handed on */
    }
    SlotState *state = &scan->seen[slot];
    if (state->block == MIR_NONE) {
      *state = (SlotState){.block = here, .confined = true, .written = false};
    }
    state->confined = state->confined && state->block == here;
    if (how == ACCESS_ESCAPE) {
      state->confined = false;
    } else if (how == ACCESS_READ) {
      state->confined = state->confined && state->written;
    } else if (how == ACCESS_WRITE) {
      state->written = true;
    }
  }
}

MirBlock *mir_confined_slots(MsArena *arena, const MirModule *module, const MirFunc *func) {
  const size_t count = func->values.len + 1;
  uint32_t *owner = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  if (!find_slots(func, owner)) {
    return NULL;
  }
  derive_owners(module, func, owner);
  SlotState *seen = MS_ARENA_NEW_ARRAY(arena, SlotState, count);
  for (size_t value = 0; value < func->values.len; value++) {
    seen[value] = (SlotState){.block = MIR_NONE};
  }
  Scan scan = {owner, seen};
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t index = 0; index < data->insts.len; index++) {
      scan_inst(module, &scan, &data->insts.ptr[index], (MirBlock)block);
    }
    mir_term_each_value(&data->term, term_use, &scan);
  }
  MirBlock *out = MS_ARENA_NEW_ARRAY(arena, MirBlock, count);
  for (size_t value = 0; value < func->values.len; value++) {
    out[value] = seen[value].block != MIR_NONE && seen[value].confined ? seen[value].block : MIR_NONE;
  }
  return out;
}
