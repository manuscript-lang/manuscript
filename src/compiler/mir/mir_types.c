/* compiler/mir/mir_types.c: the MIR type table and the opcode table.
 *
 * A type is identified by its fields (kind, id, element, name, owned bits, arguments). They are packed into
 * a byte key and interned in an MsNames, so equal types are equal ids and the table needs no hash code of its
 * own. The void type is the empty key and so is id 0. Argument arrays are copied into the module arena. */
#include "compiler/mir/mir.h"

#include "base/hash.h"

const MirOpInfo mir_op_info[MOP_COUNT] = {
#define MIR_OP(id, name, imm, res, fx) [MOP_##id] = {name, imm, res, fx},
#include "compiler/mir/mir_ops.def"
#undef MIR_OP
};

enum { KEY_HEADER_BYTES = 28, KEY_INLINE_ARGS = 16 };

static void put32(uint8_t *at, uint32_t value) {
  __builtin_memcpy(at, &value, sizeof value);
}

/* Packs `data` into `key` (KEY_HEADER_BYTES plus four bytes per argument) and returns its length. */
static size_t pack_key(const MirTyData *data, uint8_t *key) {
  if (data->kind == MK_VOID) {
    return 0;
  }
  key[0] = data->kind;
  key[1] = data->obj_class;
  key[2] = 0;
  key[3] = 0;
  put32(key + 4, data->id);
  put32(key + 8, data->elem);
  put32(key + 12, data->name);
  put32(key + 16, (uint32_t)data->owned);
  put32(key + 20, (uint32_t)(data->owned >> 32));
  put32(key + 24, data->nargs);
  for (uint32_t index = 0; index < data->nargs; index++) {
    put32(key + KEY_HEADER_BYTES + (size_t)index * 4, data->args[index]);
  }
  return KEY_HEADER_BYTES + (size_t)data->nargs * 4;
}

typedef bool (*KeyVisit)(void *state, MsSpan key);

/* Packs `data` into a stack buffer, or a heap one when it has many arguments, and hands the key to `visit`. */
static bool with_key(const MirTyData *data, KeyVisit visit, void *state) {
  uint8_t inline_key[KEY_HEADER_BYTES + KEY_INLINE_ARGS * 4];
  if (data->nargs <= KEY_INLINE_ARGS) {
    return visit(state, ms_span_of(inline_key, pack_key(data, inline_key)));
  }
  MsList heap = {0};
  uint8_t *key = ms_list_extend(&heap, 1, KEY_HEADER_BYTES + (size_t)data->nargs * 4);
  const bool result = visit(state, ms_span_of(key, pack_key(data, key)));
  ms_list_free(&heap);
  return result;
}

typedef struct InternState {
  MirModule *module;
  const MirTyData *data;
  MirTy result;
} InternState;

static bool intern_visit(void *state, MsSpan key) {
  InternState *intern = state;
  MirTyTable *table = &intern->module->types;
  const MsName id = ms_names_intern(&table->keys, key);
  if (id == table->kinds.len) {
    MirTyData *copy = MS_ARENA_NEW(&intern->module->arena, MirTyData);
    *copy = *intern->data;
    if (copy->nargs != 0) {
      MirTy *args = MS_ARENA_NEW_ARRAY(&intern->module->arena, MirTy, copy->nargs);
      __builtin_memcpy(args, copy->args, sizeof(MirTy) * copy->nargs);
      copy->args = args;
    }
    mir_tydata_list_push(&table->kinds, copy);
  }
  intern->result = id;
  return true;
}

MirTy mir_ty_intern(MirModule *module, const MirTyData *data) {
  InternState state = {.module = module, .data = data, .result = 0};
  (void)with_key(data, intern_visit, &state);
  return state.result;
}

typedef struct FindState {
  const MirModule *module;
  MirTy result;
} FindState;

static bool find_visit(void *state, MsSpan key) {
  FindState *find = state;
  MsName id = 0;
  if (!ms_names_find(&find->module->types.keys, key, &id)) {
    return false;
  }
  find->result = id;
  return true;
}

bool mir_ty_find(const MirModule *module, const MirTyData *data, MirTy *out) {
  FindState state = {.module = module, .result = 0};
  if (!with_key(data, find_visit, &state)) {
    return false;
  }
  *out = state.result;
  return true;
}

MirTy mir_ty_list(MirModule *module, MirTy elem) {
  const MirTyData data = {.kind = MK_LIST, .elem = elem};
  return mir_ty_intern(module, &data);
}

MirTy mir_ty_opt(MirModule *module, MirTy elem) {
  const MirTyData data = {.kind = MK_OPT, .elem = elem};
  return mir_ty_intern(module, &data);
}

MirTy mir_ty_type(MirModule *module, uint32_t id) {
  const MirTyData data = {.kind = MK_TYPE, .id = id};
  return mir_ty_intern(module, &data);
}

MirTy mir_ty_alt(MirModule *module, uint32_t id) {
  const MirTyData data = {.kind = MK_ALT, .id = id};
  return mir_ty_intern(module, &data);
}

MirTy mir_ty_iface(MirModule *module, uint32_t id) {
  const MirTyData data = {.kind = MK_IFACE, .id = id};
  return mir_ty_intern(module, &data);
}

/* The runtime's declaration of the objects that are not one shared word: the only place their names appear. */
static MirObjClass obj_class_of(const MirModule *module, MsName name) {
  static const struct {
    const char *name;
    MirObjClass class_of;
  } declared[] = {{"Map", MIR_OBJ_COLLECTION}, {"Set", MIR_OBJ_COLLECTION}, {"BigInt", MIR_OBJ_VALUE}};
  for (size_t index = 0; index < MS_COUNT_OF(declared); index++) {
    if (mir_name_is(module, name, declared[index].name)) {
      return declared[index].class_of;
    }
  }
  return MIR_OBJ_HANDLE;
}

MirTy mir_ty_obj(MirModule *module, MsName name, const MirTy *args, uint32_t nargs) {
  const MirTyData data = {
      .kind = MK_OBJ, .obj_class = (uint8_t)obj_class_of(module, name), .name = name, .args = args,
      .nargs = nargs};
  return mir_ty_intern(module, &data);
}

MirTy mir_ty_fn(MirModule *module, const MirTy *params, uint32_t count, MirTy ret, uint64_t owned) {
  const MirTyData data = {.kind = MK_FN, .elem = ret, .args = params, .nargs = count, .owned = owned};
  return mir_ty_intern(module, &data);
}

static bool needs_drop_in(const MirModule *module, MirTy type, MirTyList *seen);

static bool fields_need_drop(const MirModule *module, const MirField *fields, uint32_t count,
                             MirTyList *seen) {
  for (uint32_t index = 0; index < count; index++) {
    if (needs_drop_in(module, fields[index].ty, seen)) {
      return true;
    }
  }
  return false;
}

static bool alt_needs_drop(const MirModule *module, const MirAltDef *alt, MirTyList *seen) {
  for (uint32_t index = 0; index < alt->ncases; index++) {
    if (mir_owns(alt->borrowed, index)) {
      continue;
    }
    if (fields_need_drop(module, alt->cases[index].fields, alt->cases[index].nfields, seen)) {
      return true;
    }
  }
  return false;
}

/* A declaration met again while walking itself holds a pointer back to itself, which is owned. */
static bool declaration_needs_drop(const MirModule *module, MirTy type, MirTyList *seen) {
  for (size_t index = 0; index < seen->len; index++) {
    if (seen->ptr[index] == type) {
      return true;
    }
  }
  const MirTyData *data = mir_ty_data(module, type);
  mir_tylist_push(seen, type);
  const bool result = data->kind == MK_TYPE
                          ? fields_need_drop(module, module->type_defs.ptr[data->id].fields,
                                             module->type_defs.ptr[data->id].nfields, seen)
                          : alt_needs_drop(module, &module->alts.ptr[data->id], seen);
  mir_tylist_truncate(seen, seen->len - 1);
  return result;
}

static bool needs_drop_in(const MirModule *module, MirTy type, MirTyList *seen) {
  const MirTyData *data = mir_ty_data(module, type);
  switch ((MirTyKind)data->kind) {
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT: case MK_FLOAT32:
  case MK_PTR:
    return false;
  case MK_OPT:
    return needs_drop_in(module, data->elem, seen);
  case MK_TYPE:
  case MK_ALT:
    return declaration_needs_drop(module, type, seen);
  case MK_STR: case MK_BYTES: case MK_LIST: case MK_OBJ: case MK_FN: case MK_IFACE:
    return true;
  }
  return true;
}

bool mir_needs_drop(const MirModule *module, MirTy type) {
  /* Most queries are a scalar or a heap kind: answer them without the declaration walk's bookkeeping. */
  const MirTyData *data = mir_ty_data(module, type);
  while (data->kind == MK_OPT) {
    data = mir_ty_data(module, data->elem);
  }
  if (data->kind != MK_TYPE && data->kind != MK_ALT) {
    return needs_drop_in(module, type, NULL);
  }
  MirTyList seen = {0};
  const bool result = needs_drop_in(module, type, &seen);
  mir_tylist_free(&seen);
  return result;
}
