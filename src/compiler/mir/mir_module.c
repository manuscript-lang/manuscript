/* compiler/mir/mir_module.c: a MIR module and the functions inside it: construction, declarations, name
 * lookup and release.
 *
 * Declaration indexes are dense arrays by interned name id (no hashing); the first declaration of a name
 * wins. Lists that grow are base lists, freed by mir_module_free; everything else is in the module arena. */
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_analysis.h"

#include "base/fatal.h"

static const MirTyKind builtin_kinds[MIR_BUILTIN_TYPES] = {
    MK_VOID,  MK_BOOL,   MK_INT,    MK_FLOAT,  MK_STR,    MK_BYTES,  MK_PTR,   MK_INT8,
    MK_INT16, MK_INT32,  MK_FLOAT32, MK_UINT8, MK_UINT16, MK_UINT32, MK_UINT64};

void mir_module_init(MirModule *module) {
  *module = (MirModule){0};
  module->arena = ms_arena_new();
  ms_names_init(&module->names);
  ms_names_init(&module->strings);
  ms_names_init(&module->types.keys);
  module->entry = MIR_NONE;
  module->close = MIR_NONE;
  module->name = mir_name(module, ms_span_of_text("main"));
  for (size_t index = 0; index < MIR_BUILTIN_TYPES; index++) {
    const MirTyData data = {.kind = (uint8_t)builtin_kinds[index]};
    (void)mir_ty_intern(module, &data);
  }
}

void mir_module_free(MirModule *module) {
  for (size_t index = 0; index < module->funcs.len; index++) {
    mir_func_release(&module->funcs.ptr[index]);
  }
  mir_func_list_free(&module->funcs);
  mir_type_def_list_free(&module->type_defs);
  mir_alt_def_list_free(&module->alts);
  mir_obj_hook_list_free(&module->obj_hooks);
  mir_iface_def_list_free(&module->ifaces);
  mir_vtable_list_free(&module->vtables);
  mir_desc_glue_list_free(&module->desc_glue);
  ms_span_list_free(&module->files);
  ms_span_list_free(&module->blobs);
  mir_list_const_list_free(&module->list_consts);
  mir_int64list_free(&module->list_const_values);
  mir_extern_list_free(&module->externs);
  mir_global_list_free(&module->globals);
  mir_idlist_free(&module->by_func);
  mir_idlist_free(&module->by_type);
  mir_idlist_free(&module->by_alt);
  mir_idlist_free(&module->by_iface);
  mir_idlist_free(&module->by_vtable);
  mir_idlist_free(&module->by_global);
  mir_idlist_free(&module->by_extern);
  mir_tydata_list_free(&module->types.kinds);
  ms_names_free(&module->types.keys);
  ms_names_free(&module->names);
  ms_names_free(&module->strings);
  ms_arena_free(&module->arena);
  *module = (MirModule){0};
}

MsName mir_name(MirModule *module, MsSpan text) {
  return ms_names_intern(&module->names, text);
}

bool mir_name_is(const MirModule *module, MsName name, const char *text) {
  return ms_span_is_text(ms_names_span(&module->names, name), text);
}

uint32_t mir_add_string(MirModule *module, MsSpan text) {
  return ms_names_intern(&module->strings, text);
}

uint32_t mir_add_file(MirModule *module, MsSpan path) {
  const MsSpan copy = ms_arena_copy(&module->arena, path);
  ms_span_list_push(&module->files, copy);
  return (uint32_t)(module->files.len - 1);
}

/* ---- name indexes ---- */

static uint32_t index_get(const MirIdList *index, MsName name) {
  return name < index->len ? index->ptr[name] : MIR_NONE;
}

static void index_add(MirIdList *index, MsName name, uint32_t id) {
  while (index->len <= name) {
    mir_idlist_push(index, MIR_NONE);
  }
  if (index->ptr[name] == MIR_NONE) {
    index->ptr[name] = id;
  }
}

uint32_t mir_func_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_func, name);
}

uint32_t mir_type_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_type, name);
}

uint32_t mir_alt_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_alt, name);
}

uint32_t mir_iface_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_iface, name);
}

uint32_t mir_vtable_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_vtable, name);
}

uint32_t mir_global_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_global, name);
}

uint32_t mir_extern_by_name(const MirModule *module, MsName name) {
  return index_get(&module->by_extern, name);
}

/* ---- declarations ---- */

uint32_t mir_add_func(MirModule *module, const MirFunc *func) {
  mir_func_list_push(&module->funcs, *func);
  const uint32_t id = (uint32_t)(module->funcs.len - 1);
  index_add(&module->by_func, func->name, id);
  return id;
}

void mir_funcs_reindex(MirModule *module) {
  mir_idlist_clear(&module->by_func);
  for (size_t index = 0; index < module->funcs.len; index++) {
    index_add(&module->by_func, module->funcs.ptr[index].name, (uint32_t)index);
  }
}

uint32_t mir_add_type(MirModule *module, MsName name) {
  mir_type_def_list_push(&module->type_defs, (MirTypeDef){.name = name});
  const uint32_t id = (uint32_t)(module->type_defs.len - 1);
  index_add(&module->by_type, name, id);
  return id;
}

uint32_t mir_add_alt(MirModule *module, MsName name) {
  mir_alt_def_list_push(&module->alts, (MirAltDef){.name = name});
  const uint32_t id = (uint32_t)(module->alts.len - 1);
  index_add(&module->by_alt, name, id);
  return id;
}

uint32_t mir_add_iface(MirModule *module, MsName name) {
  mir_iface_def_list_push(&module->ifaces, (MirIfaceDef){.name = name});
  const uint32_t id = (uint32_t)(module->ifaces.len - 1);
  index_add(&module->by_iface, name, id);
  return id;
}

uint32_t mir_add_vtable(MirModule *module, const MirVtable *vtable) {
  mir_vtable_list_push(&module->vtables, *vtable);
  const uint32_t id = (uint32_t)(module->vtables.len - 1);
  index_add(&module->by_vtable, vtable->name, id);
  return id;
}

uint32_t mir_add_global(MirModule *module, MsName name, MirTy type) {
  mir_global_list_push(&module->globals, (MirGlobal){name, type});
  const uint32_t id = (uint32_t)(module->globals.len - 1);
  index_add(&module->by_global, name, id);
  return id;
}

uint32_t mir_add_extern(MirModule *module, const MirExtern *external) {
  mir_extern_list_push(&module->externs, *external);
  const uint32_t id = (uint32_t)(module->externs.len - 1);
  index_add(&module->by_extern, external->name, id);
  return id;
}

void mir_add_desc_glue(MirModule *module, MirTy type, uint32_t eq, uint32_t hash) {
  mir_desc_glue_list_push(&module->desc_glue, (MirDescGlue){type, eq, hash});
}

/* ---- functions ---- */

MirValue mir_new_value(MirFunc *func, MirTy type) {
  mir_tylist_push(&func->values, type);
  return (MirValue)(func->values.len - 1);
}

MirBlockData mir_block_empty(void) {
  MirBlockData block = {0};
  block.term.kind = MT_UNREACHABLE;
  block.term.value = MIR_NONE;
  block.term_loc = MIR_LOC_NONE;
  return block;
}

MirBlock mir_new_block(MirFunc *func) {
  mir_block_list_push(&func->blocks, mir_block_empty());
  return (MirBlock)(func->blocks.len - 1);
}

void mir_func_init(MirModule *module, MirFunc *func, MsName name, const MirParam *params, uint32_t count,
                   MirTy ret) {
  *func = (MirFunc){0};
  func->name = name;
  func->params = MS_ARENA_NEW_ARRAY(&module->arena, MirParam, count);
  if (count != 0) {
    __builtin_memcpy(func->params, params, sizeof(MirParam) * count);
  }
  func->nparams = count;
  func->ret = ret;
  func->loc = MIR_LOC_NONE;
  const MirBlock entry = mir_new_block(func);
  for (uint32_t index = 0; index < count; index++) {
    const MirBlockParam param = {mir_new_value(func, params[index].ty), params[index].mode};
    mir_block_param_list_push(&func->blocks.ptr[entry].params, param);
  }
}

/* ---- terminators ---- */

void mir_target_remove_arg(MirTarget *t, uint32_t k) {
  __builtin_memmove(&t->args[k], &t->args[k + 1], sizeof(MirValue) * (t->nargs - k - 1));
  t->nargs--;
}

uint32_t mir_term_ntargets(const MirTerm *term) {
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    return 1;
  case MT_CONDBR:
    return 2;
  case MT_SWITCH:
    return term->ncases + 1;
  case MT_RET: case MT_FAULT: case MT_UNREACHABLE:
    return 0;
  }
  return 0;
}

MirTarget *mir_term_target(MirTerm *term, uint32_t index) {
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    return &term->a;
  case MT_CONDBR:
    return index == 0 ? &term->a : &term->b;
  case MT_SWITCH:
    return index < term->ncases ? &term->cases[index].target : &term->b;
  case MT_RET: case MT_FAULT: case MT_UNREACHABLE:
    break;
  }
  ms_fatal(MS_FATAL_INVARIANT, "mir_term_target: terminator has no targets");
}
