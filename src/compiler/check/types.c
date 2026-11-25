/* compiler/check/types.c: the type table (interning) and the nominal definitions of types.h.
 *
 * A type's structure is packed into a word key and interned in `keys`, so the key table is the hash table
 * and the row number is the key's name id. */
#include "compiler/check/types.h"

#include "base/alloc.h"
#include "base/fatal.h"

const char *ms_ty_kind_name(MsTyKind kind) {
  switch (kind) {
  case MS_TY_PRIMITIVE:
    return "primitive";
  case MS_TY_INVALID:
    return "invalid";
  case MS_TY_INFERRED:
    return "inferred";
  case MS_TY_VARIABLE:
    return "variable";
  case MS_TY_TYPE:
    return "type";
  case MS_TY_ALTERNATIVE:
    return "alternative";
  case MS_TY_CONTRACT:
    return "contract";
  case MS_TY_FUNCTION:
    return "function";
  case MS_TY_NATIVE:
    return "native";
  }
  return "invalid";
}

void ms_tys_init(MsTyTable *table) {
  *table = (MsTyTable){0};
  ms_names_init(&table->keys);
  ms_ty_row_list_push(&table->rows, (MsTyRow){.kind = MS_TY_INVALID, .open = false});
  ms_ty_variable_list_push(&table->variables, (MsTyVariable){0});
}

void ms_tys_free(MsTyTable *table) {
  for (size_t index = 0; index < table->variables.len; index++) {
    ms_ty_list_free(&table->variables.ptr[index].bounds);
  }
  ms_names_free(&table->keys);
  ms_ty_row_list_free(&table->rows);
  ms_ty_list_free(&table->args_pool);
  ms_ty_param_list_free(&table->params_pool);
  ms_ty_variable_list_free(&table->variables);
  ms_word_list_free(&table->key_words);
  ms_ty_list_free(&table->scratch);
  ms_ty_param_list_free(&table->param_scratch);
}

static uint32_t param_word(const MsTyParam *param) {
  return (uint32_t)param->flags;
}

/* Packs the identity of `desc` into table->key_words: id, kind, counts, parameters, result, arguments. */
static MsSpan pack_key(MsTyTable *table, const MsTyDesc *desc) {
  MsWordList *words = &table->key_words;
  ms_word_list_clear(words);
  ms_word_list_push(words, desc->id);
  ms_word_list_push(words, (uint32_t)desc->kind);
  ms_word_list_push(words, desc->param_count);
  ms_word_list_push(words, desc->arg_count);
  for (uint32_t index = 0; index < desc->param_count; index++) {
    ms_word_list_push(words, desc->params[index].ty);
    ms_word_list_push(words, param_word(&desc->params[index]));
  }
  ms_word_list_push(words, desc->result);
  for (uint32_t index = 0; index < desc->arg_count; index++) {
    ms_word_list_push(words, desc->args[index]);
  }
  return ms_span_of((const uint8_t *)words->ptr, words->len * sizeof(uint32_t));
}

static bool is_open(const MsTyTable *table, const MsTyDesc *desc) {
  if (desc->kind == MS_TY_VARIABLE || ms_ty_row(table, desc->result)->open) {
    return true;
  }
  for (uint32_t index = 0; index < desc->arg_count; index++) {
    if (ms_ty_row(table, desc->args[index])->open) {
      return true;
    }
  }
  for (uint32_t index = 0; index < desc->param_count; index++) {
    if (ms_ty_row(table, desc->params[index].ty)->open) {
      return true;
    }
  }
  return false;
}

static void add_row(MsTyTable *table, const MsTyDesc *desc) {
  MsTyRow row = {.name = desc->name, .id = desc->id, .kind = (uint8_t)desc->kind,
                 .builtin = (uint8_t)desc->builtin, .open = is_open(table, desc), .def = desc->def,
                 .result = desc->result, .arg_count = desc->arg_count, .param_count = desc->param_count};
  row.args_at = (uint32_t)table->args_pool.len;
  row.params_at = (uint32_t)table->params_pool.len;
  for (uint32_t index = 0; index < desc->arg_count; index++) {
    ms_ty_list_push(&table->args_pool, desc->args[index]);
  }
  for (uint32_t index = 0; index < desc->param_count; index++) {
    ms_ty_param_list_push(&table->params_pool, desc->params[index]);
  }
  ms_ty_row_list_push(&table->rows, row);
}

MsTy ms_ty_intern(MsTyTable *table, const MsTyDesc *desc) {
  /* `T??` is `T?`: a nullable of a nullable is the same type. */
  if (desc->builtin == MS_BUILTIN_Optional && desc->arg_count == 1 && ms_ty_row(table, desc->args[0])->builtin == (uint8_t)MS_BUILTIN_Optional) {
    return desc->args[0];
  }
  if (desc->builtin == MS_BUILTIN_Ref && desc->arg_count == 1) {
    /* `&&T` is `&T`, and a borrow of a scalar is the scalar: a copy of one is a borrow. */
    const MsTyRow *inner = ms_ty_row(table, desc->args[0]);
    if (inner->builtin == (uint8_t)MS_BUILTIN_Ref || ms_builtin_is_int((MsBuiltin)inner->builtin) ||
        ms_builtin_is_float((MsBuiltin)inner->builtin) || inner->builtin == (uint8_t)MS_BUILTIN_Bool ||
        inner->kind == MS_TY_INVALID) {
      return desc->args[0];
    }
  }
  const MsName row = ms_names_intern(&table->keys, pack_key(table, desc));
  if (row == table->rows.len) {
    add_row(table, desc);
  }
  return row;
}

bool ms_ty_same_view(const MsTyTable *table, MsTy a, MsTy b) {
  while (ms_ty_is_borrow(table, a)) {
    a = ms_ty_args(table, a)[0];
  }
  while (ms_ty_is_borrow(table, b)) {
    b = ms_ty_args(table, b)[0];
  }
  if (a == b) {
    return true;
  }
  const MsTyRow *left = ms_ty_row(table, a);
  const MsTyRow *right = ms_ty_row(table, b);
  if (left->id != right->id || left->kind != right->kind || left->arg_count != right->arg_count ||
      left->param_count != right->param_count ||
      (left->kind != MS_TY_FUNCTION && left->arg_count == 0)) {
    return false;
  }
  for (uint32_t index = 0; index < left->arg_count; index++) {
    if (!ms_ty_same_view(table, ms_ty_args(table, a)[index], ms_ty_args(table, b)[index])) {
      return false;
    }
  }
  for (uint32_t index = 0; index < left->param_count; index++) {
    if (ms_ty_params(table, a)[index].flags != ms_ty_params(table, b)[index].flags ||
        !ms_ty_same_view(table, ms_ty_params(table, a)[index].ty, ms_ty_params(table, b)[index].ty)) {
      return false;
    }
  }
  return left->kind != MS_TY_FUNCTION || ms_ty_same_view(table, left->result, right->result);
}

MsTy ms_ty_ref(MsTyTable *table, MsTy inner) {
  /* no name: it is shown as `&inner`, and its identity is its kind, builtin and argument */
  const MsTyDesc desc = {.kind = MS_TY_NATIVE, .builtin = MS_BUILTIN_Ref, .args = &inner, .arg_count = 1};
  return ms_ty_intern(table, &desc);
}

MsTy ms_ty_shape(MsTyTable *table, MsTy ty) {
  ty = ms_ty_unref(table, ty); /* `List[&T]` and `List[T]` have one shape: a borrow reads as the value */
  const MsTyRow *row = ms_ty_row(table, ty);
  bool lifted = false;
  for (uint32_t index = 0; index < row->param_count; index++) {
    lifted = lifted || (table->params_pool.ptr[row->params_at + index].flags & MS_PARAM_LIFTED) != 0;
  }
  if (!lifted) {
    return ty;
  }
  const size_t mark = table->param_scratch.len;
  for (uint32_t index = 0; index < row->param_count; index++) {
    MsTyParam param = table->params_pool.ptr[row->params_at + index];
    param.flags = (uint8_t)(param.flags & ~MS_PARAM_LIFTED);
    ms_ty_param_list_push(&table->param_scratch, param);
  }
  row = ms_ty_row(table, ty);
  const MsTyDesc desc = {.name = row->name, .id = row->id, .kind = (MsTyKind)row->kind,
                         .builtin = (MsBuiltin)row->builtin, .def = row->def,
                         .args = table->args_pool.ptr + row->args_at, .arg_count = row->arg_count,
                         .params = table->param_scratch.ptr + mark, .param_count = row->param_count,
                         .result = row->result};
  const MsTy shaped = ms_ty_intern(table, &desc);
  ms_ty_param_list_truncate(&table->param_scratch, mark);
  return shaped;
}

MsTy ms_ty_variable_new(MsTyTable *table, MsName name, MsName id) {
  const uint32_t slot = (uint32_t)table->variables.len;
  const MsTyDesc desc = {.name = name, .id = id, .kind = MS_TY_VARIABLE, .def = slot};
  const size_t before = table->rows.len;
  const MsTy ty = ms_ty_intern(table, &desc);
  if (ty == before) {
    ms_ty_variable_list_push(&table->variables, (MsTyVariable){0});
  }
  return ty;
}

MsTyVariable *ms_ty_variable(MsTyTable *table, MsTy ty) {
  const MsTyRow *row = ms_ty_row(table, ty);
  return row->kind == MS_TY_VARIABLE ? &table->variables.ptr[row->def] : NULL;
}

/* ---- definitions ---- */

void ms_defs_init(MsDefs *defs) {
  *defs = (MsDefs){.arena = ms_arena_new()};
  defs->capacity = 16;
  defs->by_index = ms_alloc_zeroed(defs->capacity * sizeof(MsDef *));
  defs->count = 1;
}

void ms_defs_free(MsDefs *defs) {
  for (size_t index = 1; index < defs->count; index++) {
    MsDef *def = defs->by_index[index];
    ms_ty_list_free(&def->variables);
    ms_ty_param_list_free(&def->fields);
    for (size_t at = 0; at < def->cases.len; at++) {
      ms_ty_param_list_free(&def->cases.ptr[at].fields);
    }
    ms_ty_case_list_free(&def->cases);
    for (size_t at = 0; at < def->operations.len; at++) {
      ms_ty_list_free(&def->operations.ptr[at].variables);
    }
    ms_operation_list_free(&def->operations);
  }
  ms_free(defs->by_index);
  ms_arena_free(&defs->arena);
  *defs = (MsDefs){0};
}

uint32_t ms_defs_add(MsDefs *defs, MsTyKind kind, uint32_t symbol) {
  if (defs->count == defs->capacity) {
    size_t bytes = 0;
    if (!ms_size_mul(defs->capacity * 2, sizeof(MsDef *), &bytes)) {
      ms_fatal(MS_FATAL_OVERFLOW, "too many definitions");
    }
    defs->by_index = ms_realloc(defs->by_index, bytes);
    defs->capacity *= 2;
  }
  MsDef *def = MS_ARENA_NEW(&defs->arena, MsDef);
  def->kind = kind;
  def->symbol = symbol;
  defs->by_index[defs->count] = def;
  return (uint32_t)defs->count++;
}

MsDef *ms_defs_get(const MsDefs *defs, uint32_t index) {
  if (index == 0 || index >= defs->count) {
    ms_fatal(MS_FATAL_OUT_OF_RANGE, "definition index out of range");
  }
  return defs->by_index[index];
}

bool ms_def_find_case(const MsDef *def, MsName name, size_t *index) {
  for (size_t at = 0; at < def->cases.len; at++) {
    if (def->cases.ptr[at].name == name) {
      *index = at;
      return true;
    }
  }
  return false;
}
