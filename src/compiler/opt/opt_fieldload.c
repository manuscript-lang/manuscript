/* opt_fieldload.c: the `fieldload` pass. A field of a record behind a pointer is loaded alone, not through a whole
 * copy of the record.
 *
 * `r = load T p; f = type.get T.f r` copies every leaf of `T` into a cell to read the leaves of one field. When `r`
 * has no other use and nothing between the load and the read can change what `p` points to, the read is
 * `a = ptr.field T.f p; f = load F a`, which touches only the field. The field must lie in the record's memory image
 * the way it lies alone (the leaves keep their distances), and the record must be inline (not behind a pointer). */
#include "compiler/mir/mir_layout.h"
#include "compiler/opt/opt_pass.h"

/* Whether an instruction can change memory a load read, or hand control to code that can. */
static bool may_change_memory(const MirInst *inst) {
  return mir_op_is_call((MirOp)inst->op) || (mir_op_info[inst->op].effects & (MIR_E_WRITES | MIR_E_IO)) != 0;
}

/* Whether field `field` of record `type_id` lies in the record's memory image as it lies alone. */
static bool field_lies_alone(MirLayouts *layouts, uint32_t type_id, uint32_t field) {
  const MirRecordBlock block = mir_record_block(layouts, type_id);
  if (block.boxed[field]) {
    return false;
  }
  const MsSpan leaves = mir_leaves(layouts, block.def->fields[field].ty);
  if (leaves.len == 0) {
    return false;
  }
  uint32_t *alone = MS_ARENA_NEW_ARRAY(&layouts->arena, uint32_t, leaves.len + 1);
  (void)mir_mem_layout(leaves, alone);
  const uint32_t start = block.starts[field];
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    if (block.offsets[start + leaf] - block.offsets[start] != alone[leaf]) {
      return false;
    }
  }
  return true;
}

/* The `type.get`s of loaded record `r` after position `at`, all in the block with no change of memory before the last;
 * false when `r` has any other use. */
static bool reads_only_fields(const MirBlockData *block, uint32_t at, uint32_t uses) {
  const MirValue loaded = block->insts.ptr[at].res;
  uint32_t found = 0;
  bool changed = false;
  for (uint32_t i = at + 1; i < block->insts.len && found < uses; i++) {
    const MirInst *inst = &block->insts.ptr[i];
    bool mentions = false;
    for (uint32_t arg = 0; arg < inst->nargs; arg++) {
      mentions |= inst->args[arg] == loaded;
    }
    if (mentions) {
      if (changed || inst->op != MOP_TypeGet || inst->nargs != 1 || inst->imm.tag != MI_FIELD) {
        return false;
      }
      found++;
    } else {
      changed |= may_change_memory(inst);
    }
  }
  return found == uses;
}

static bool rewrite_block(MirModule *m, MirFunc *f, MirLayouts *layouts, const uint32_t *use_counts, uint32_t bi) {
  bool changed = false;
  MirBlockData *block = &f->blocks.ptr[bi];
  for (uint32_t at = 0; at < block->insts.len; at++) {
    const MirInst load = block->insts.ptr[at];
    if (load.op != MOP_Load || load.nargs != 1 || load.res == MIR_NONE || load.imm.tag != MI_TY ||
        use_counts[load.res] == 0) {
      continue;
    }
    const MirTyData *data = mir_ty_data(m, f->values.ptr[load.res]);
    if (data->kind != MK_TYPE || m->type_defs.ptr[data->id].indirect || !reads_only_fields(block, at, use_counts[load.res])) {
      continue;
    }
    bool lies = true;
    for (uint32_t i = at + 1; i < block->insts.len && lies; i++) {
      const MirInst *get = &block->insts.ptr[i];
      lies = get->op != MOP_TypeGet || get->args[0] != load.res || field_lies_alone(layouts, get->imm.a, get->imm.b);
    }
    if (!lies) {
      continue;
    }
    for (uint32_t i = at + 1; i < block->insts.len; i++) {
      MirInst *get = &block->insts.ptr[i];
      if (get->op != MOP_TypeGet || get->args[0] != load.res) {
        continue;
      }
      const MirValue address = mir_new_value(f, MIR_PTR);
      const MirTy field_ty = f->values.ptr[get->res];
      const MirInst field = opt_inst_make(m, MOP_PtrField, &load.args[0], 1, get->imm, address, get->loc);
      *get = opt_inst_make(m, MOP_Load, &address, 1, (MirImm){.tag = MI_TY, .a = field_ty}, get->res, get->loc);
      mir_block_insert(block, i, &field);
      i++;
    }
    changed = true;
  }
  return changed;
}

bool opt_fieldload(MirModule *m) {
  bool changed = false;
  MirLayouts layouts;
  bool ready = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    bool any = false;
    for (uint32_t bi = 0; bi < f->blocks.len && !any; bi++) {
      for (uint32_t i = 0; i < f->blocks.ptr[bi].insts.len && !any; i++) {
        any = f->blocks.ptr[bi].insts.ptr[i].op == MOP_Load;
      }
    }
    if (!any) {
      continue;
    }
    if (!ready) {
      mir_layouts_init(&layouts, m);
      ready = true;
    }
    MsArena arena = ms_arena_new();
    const uint32_t *uses = mir_use_counts(&arena, f);
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      changed |= rewrite_block(m, f, &layouts, uses, bi);
    }
    ms_arena_free(&arena);
  }
  if (ready) {
    mir_layouts_free(&layouts);
  }
  return changed;
}
