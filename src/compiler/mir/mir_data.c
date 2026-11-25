/* compiler/mir/mir_data.c: descriptors, vtables, globals and unit blocks. */
#include "compiler/mir/mir_data_internal.h"

#include "base/strbuild.h"

void mir_data_free(MirData *data) {
  mir_data_sym_list_free(&data->syms);
  mir_idlist_free(&data->globals);
  mir_idlist_free(&data->vtables);
  mir_unit_list_free(&data->units);
  mir_idlist_free(&data->blobs);
  mir_idlist_free(&data->list_consts);
  mir_idlist_free(&data->strings);
  mir_desc_map_free(&data->descs);
  mir_desc_map_free(&data->shapes);
}

uint32_t mird_add_sym(DataCx *cx, const MirDataSym *sym) {
  mir_data_sym_list_push(&cx->data->syms, *sym);
  return (uint32_t)cx->data->syms.len - 1;
}

MsSpan mird_name(DataCx *cx, const char *kind, uint32_t n) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "ms.%s.%u", kind, n);
  const MsSpan name = ms_arena_copy(&cx->module->arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

static void mird_put_word(uint8_t *at, uint64_t value) {
  for (uint32_t index = 0; index < 8; index++) {
    at[index] = (uint8_t)(value >> (8 * index));
  }
}

void mird_fill_none(MirIdList *list, size_t count) {
  for (size_t index = 0; index < count; index++) {
    mir_idlist_push(list, MIR_NONE);
  }
}

void mird_each_inst(DataCx *cx, MirdInstFn visit) {
  const MirModule *module = cx->module;
  for (size_t fi = 0; fi < module->funcs.len; fi++) {
    const MirFunc *func = &module->funcs.ptr[fi];
    for (size_t bi = 0; bi < func->blocks.len; bi++) {
      const MirBlockData *block = &func->blocks.ptr[bi];
      for (size_t ii = 0; ii < block->insts.len; ii++) {
        visit(cx, func, &block->insts.ptr[ii]);
      }
    }
  }
}

/* ---- descriptors ---- */

static MirReloc func_reloc(uint32_t offset, uint32_t func) {
  return (MirReloc){offset, {.kind = MREF_FUNC, .index = func}};
}

static void add_reloc(DataCx *cx, uint32_t sym, MirReloc reloc) {
  MirDataSym *entry = &cx->data->syms.ptr[sym];
  entry->relocs[entry->nrelocs++] = reloc;
}

/* The symbol of a descriptor the runtime does not define: size and alignment, kind, then room for the six
 * addresses. */
static uint32_t new_descriptor(DataCx *cx, const MirDescPlan *plan) {
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, MIR_DESC_BYTES);
  mird_put_word(bytes, (uint64_t)plan->size | (uint64_t)plan->align << 32);
  mird_put_word(bytes + 8, plan->kind);
  const MirDataSym sym = {.name = mird_name(cx, "desc", (uint32_t)cx->data->syms.len),
                          .size = MIR_DESC_BYTES,
                          .align = 8,
                          .bytes = ms_span_of(bytes, MIR_DESC_BYTES),
                          .relocs = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirReloc, 6)};
  return mird_add_sym(cx, &sym);
}

static MirRef descriptor_of(DataCx *cx, MirTy key);

/* Names what a recorded descriptor points at: its inner descriptors, slot glue, equality and hash. */
static void point_descriptor(DataCx *cx, uint32_t sym, const MirDescPlan *plan) {
  for (uint32_t index = 0; index < 2; index++) {
    if (plan->inner[index] != MIR_NONE) {
      const MirRef inner = descriptor_of(cx, plan->inner[index]);
      add_reloc(cx, sym, (MirReloc){index == 0 ? MIR_DESC_INNER0 : MIR_DESC_INNER1, inner});
    }
  }
  if (plan->slot_glue != MIR_NONE) {
    const uint32_t drop = mir_glue_find(cx->glue, MG_SLOT_DROP, plan->slot_glue, 0, 0);
    const uint32_t copy = mir_glue_find(cx->glue, MG_SLOT_COPY, plan->slot_glue, 0, 0);
    add_reloc(cx, sym, func_reloc(MIR_DESC_DROP, drop));
    add_reloc(cx, sym, func_reloc(MIR_DESC_COPY, copy));
  }
  if (plan->has_eq_hash) {
    add_reloc(cx, sym, func_reloc(MIR_DESC_EQ, plan->eq));
    add_reloc(cx, sym, func_reloc(MIR_DESC_HASH, plan->hash));
  }
}

MirRef mird_descriptor(DataCx *cx, MirTy key) {
  return descriptor_of(cx, key);
}

static MirRef descriptor_of(DataCx *cx, MirTy key) {
  const MirRef *known = mir_desc_map_get(&cx->data->descs, key);
  if (known != NULL) {
    return *known;
  }
  const MirDescPlan plan = mir_desc_plan(cx->module, cx->layouts, key);
  MirRef to = {.kind = MREF_RUNTIME, .runtime = plan.runtime};
  if (plan.runtime.len == 0) {
    to = (MirRef){.kind = MREF_DATA, .index = new_descriptor(cx, &plan)};
  }
  /* The symbol exists and the key is recorded before what it points at is named. */
  mir_desc_map_put(&cx->data->descs, key, to);
  if (plan.runtime.len == 0) {
    point_descriptor(cx, to.index, &plan);
  }
  return to;
}

static void visit_descriptor(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  (void)func;
  if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY) {
    (void)descriptor_of(cx, inst->imm.a);
  }
}

MirRef mir_data_desc(const MirData *data, MirTy key) {
  const MirRef *found = mir_desc_map_get(&data->descs, key);
  return found != NULL ? *found : (MirRef){.kind = MREF_RUNTIME};
}

/* ---- vtables and globals ---- */

/* Slot 0 is the payload block's drop, the methods follow, then the payload clone. */
static void build_vtables(DataCx *cx) {
  const MirModule *module = cx->module;
  for (size_t index = 0; index < module->vtables.len; index++) {
    const MirVtable *vtable = &module->vtables.ptr[index];
    const MirTy data_ty = mir_ty_unscoped(vtable->data_ty);
    const uint32_t nslots = vtable->nmethods + 2;
    /* The payload's size in bytes follows the clone: `iface.own` copies the leaves of a payload it only borrows. */
    uint8_t *size_word = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, (size_t)(nslots + 1) * 8);
    mird_put_word(size_word + (size_t)nslots * 8, mir_type_mem(cx->layouts, data_ty).size);
    MirDataSym sym = {.name = mird_name(cx, "vtable", (uint32_t)index),
                      .size = (nslots + 1) * 8,
                      .align = 8,
                      .bytes = ms_span_of(size_word, (size_t)(nslots + 1) * 8),
                      .relocs = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirReloc, nslots)};
    sym.relocs[sym.nrelocs++] = func_reloc(0, vtable->close_drop != 0 ? vtable->close_drop - 1
                                                                     : mir_glue_find(cx->glue, MG_BLOCK_DROP, data_ty, 0, 0));
    for (uint32_t method = 0; method < vtable->nmethods; method++) {
      sym.relocs[sym.nrelocs++] = func_reloc((method + 1) * 8, vtable->methods[method]);
    }
    const uint32_t clone = mir_glue_find(cx->glue, MG_BLOCK_CLONE, data_ty, 0, 0);
    sym.relocs[sym.nrelocs++] = func_reloc((vtable->nmethods + 1) * 8, clone);
    mir_idlist_push(&cx->data->vtables, mird_add_sym(cx, &sym));
  }
}

static void build_globals(DataCx *cx) {
  const MirModule *module = cx->module;
  for (size_t index = 0; index < module->globals.len; index++) {
    const uint32_t size = mir_type_mem(cx->layouts, module->globals.ptr[index].ty).size;
    const MirDataSym sym = {.name = mird_name(cx, "global", (uint32_t)index),
                            .size = size < 8 ? 8 : size,
                            .align = 8,
                            .writable = true};
    mir_idlist_push(&cx->data->globals, mird_add_sym(cx, &sym));
  }
}

/* ---- unit blocks ---- */

uint32_t mir_data_unit(const MirData *data, uint32_t alt, uint32_t case_index) {
  for (size_t index = 0; index < data->units.len; index++) {
    const MirUnit *unit = &data->units.ptr[index];
    if (unit->alt == alt && unit->case_index == case_index) {
      return unit->sym;
    }
  }
  return MIR_NONE;
}

/* A payloadless case of a boxed alternative is one static block, so building it allocates nothing. */
static void visit_unit(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  if (inst->op != MOP_AltNew && inst->op != MOP_AltView) {
    return;
  }
  const uint32_t alt = inst->imm.a;
  const uint32_t case_index = inst->imm.b;
  uint32_t size = 0;
  if (cx->module->alts.ptr[alt].cases[case_index].nfields != 0 ||
      mir_data_unit(cx->data, alt, case_index) != MIR_NONE ||
      !mir_boxed_block_size(cx->layouts, mir_value_ty(func, inst->res), &size)) {
    return;
  }
  size = size < 8 ? 8 : size;
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, size);
  mird_put_word(bytes, case_index);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "ms.unit.%u.%u", alt, case_index);
  const MirDataSym sym = {.name = ms_arena_copy(&cx->module->arena, ms_strbuild_span(&text)),
                          .size = size,
                          .align = 8,
                          .bytes = ms_span_of(bytes, size)};
  ms_strbuild_free(&text);
  mir_unit_list_push(&cx->data->units, (MirUnit){alt, case_index, mird_add_sym(cx, &sym)});
}

/* ---- the entry ---- */

void mir_data_build(MirModule *module, const MirGlue *glue, MirData *out) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  *out = (MirData){0};
  DataCx cx = {.module = module, .glue = glue, .layouts = &layouts, .data = out};
  build_globals(&cx);
  build_vtables(&cx);
  mird_constants(&cx);
  mird_each_inst(&cx, visit_unit);
  mird_each_inst(&cx, visit_descriptor);
  mird_each_inst(&cx, mird_visit_shape);
  mir_layouts_free(&layouts);
}
