/* compiler/mir/mir_boxing.c: boxing of recursive alternatives and optionals. Owns the memo tables of a
 * MirBoxing; the module it reads belongs to the caller. */
#include "compiler/mir/mir_layout.h"

void mir_boxing_init(MirBoxing *boxing, const MirModule *module) {
  *boxing = (MirBoxing){.module = module, .arena = ms_arena_new()};
  boxing->alts = MS_ARENA_NEW_ARRAY(&boxing->arena, uint8_t, module->alts.len + 1);
  boxing->opts = MS_ARENA_NEW_ARRAY(&boxing->arena, uint8_t, module->types.kinds.len + 1);
}

void mir_boxing_free(MirBoxing *boxing) {
  ms_arena_free(&boxing->arena);
  *boxing = (MirBoxing){0};
}

static bool seen_has(const MirTyList *seen, MirTy type) {
  for (size_t index = 0; index < seen->len; index++) {
    if (seen->ptr[index] == type) {
      return true;
    }
  }
  return false;
}

static bool reaches_by_value(MirBoxing *boxing, MirTy from, MirTy target, MirTyList *seen);

/* One field type of the type being searched: true when it is the target or leads to it by value. */
static bool reaches_through(MirBoxing *boxing, MirTy child, MirTy target, MirTyList *seen) {
  if (child == target) {
    return true;
  }
  if (seen_has(seen, child)) {
    return false;
  }
  mir_tylist_push(seen, child);
  const MirTyData *data = mir_ty_data(boxing->module, child);
  /* Another boxed alternative or optional is one pointer: the search stops there. */
  if (data->kind == MK_ALT && mir_boxing_alt(boxing, data->id)) {
    return false;
  }
  if (data->kind == MK_OPT && mir_boxing_opt(boxing, data->elem)) {
    return false;
  }
  return reaches_by_value(boxing, child, target, seen);
}

static bool reaches_in_fields(MirBoxing *boxing, const MirField *fields, uint32_t count, MirTy target,
                              MirTyList *seen) {
  for (uint32_t index = 0; index < count; index++) {
    if (reaches_through(boxing, fields[index].ty, target, seen)) {
      return true;
    }
  }
  return false;
}

static bool reaches_in_alt(MirBoxing *boxing, const MirAltDef *def, MirTy target, MirTyList *seen) {
  for (uint32_t index = 0; index < def->ncases; index++) {
    if (reaches_in_fields(boxing, def->cases[index].fields, def->cases[index].nfields, target, seen)) {
      return true;
    }
  }
  return false;
}

static bool reaches_by_value_inner(MirBoxing *boxing, const MirTyData *data, MirTy target, MirTyList *seen) {
  const MirModule *module = boxing->module;
  switch ((MirTyKind)data->kind) {
  case MK_TYPE:
    return reaches_in_fields(boxing, module->type_defs.ptr[data->id].fields,
                             module->type_defs.ptr[data->id].nfields, target, seen);
  case MK_ALT:
    return reaches_in_alt(boxing, &module->alts.ptr[data->id], target, seen);
  case MK_OPT:
    return reaches_through(boxing, data->elem, target, seen);
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_STR:
  case MK_BYTES: case MK_PTR: case MK_LIST: case MK_OBJ: case MK_FN: case MK_IFACE:
    return false;
  }
  return false;
}

static bool reaches_by_value(MirBoxing *boxing, MirTy from, MirTy target, MirTyList *seen) {
  if (boxing->depth >= MIR_LAYOUT_MAX_DEPTH) {
    boxing->failed = true;
    return false;
  }
  boxing->depth++;
  const bool found = reaches_by_value_inner(boxing, mir_ty_data(boxing->module, from), target, seen);
  boxing->depth--;
  return found;
}

/* Whether the type `target` contains itself by value, starting a fresh visit list. */
static bool contains_itself(MirBoxing *boxing, MirTy target) {
  MirTyList seen = {0};
  const bool found = reaches_by_value(boxing, target, target, &seen);
  mir_tylist_free(&seen);
  return found;
}

bool mir_boxing_alt(MirBoxing *boxing, uint32_t alt) {
  if (alt >= boxing->module->alts.len) {
    return false;
  }
  if (boxing->alts[alt] != 0) {
    return boxing->alts[alt] == 2;
  }
  boxing->alts[alt] = 1; /* provisional answer for cycles through other alternatives */
  const MirTyData key = {.kind = MK_ALT, .id = alt};
  MirTy type = 0;
  const bool boxed = mir_ty_find(boxing->module, &key, &type) && contains_itself(boxing, type);
  boxing->alts[alt] = boxed ? 2 : 1;
  return boxed;
}

bool mir_boxing_opt(MirBoxing *boxing, MirTy inner) {
  if (inner >= boxing->module->types.kinds.len) {
    return false;
  }
  if (boxing->opts[inner] != 0) {
    return boxing->opts[inner] == 2;
  }
  boxing->opts[inner] = 1;
  const MirTyData key = {.kind = MK_OPT, .elem = inner};
  MirTy type = 0;
  const bool boxed = mir_ty_find(boxing->module, &key, &type) && contains_itself(boxing, type);
  boxing->opts[inner] = boxed ? 2 : 1;
  return boxed;
}
