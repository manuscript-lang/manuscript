/* compiler/check/type_ops.c: showing a type as source reads it, and substituting type variables. */
#include "compiler/check/types.h"

enum { SHOW_NODE_BUDGET = 64 };

static void show_node(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty, int *budget);

static void show_function(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty,
                          int *budget) {
  ms_strbuild_append_text(out, "fn(");
  const MsTyParam *params = ms_ty_params(table, ty);
  for (size_t index = 0; index < ms_ty_param_count(table, ty); index++) {
    if (index > 0) {
      ms_strbuild_append_text(out, ", ");
    }
    ms_strbuild_append_text(out, (params[index].flags & MS_PARAM_MOVE) != 0 ? "move " : "");
    ms_strbuild_append_text(out, (params[index].flags & MS_PARAM_VAR) != 0 ? "var " : "");
    show_node(out, names, table, params[index].ty, budget);
  }
  ms_strbuild_append_text(out, ") ");
  if (ms_ty_result(table, ty) == MS_TY_NONE) {
    ms_strbuild_append_text(out, "<unknown>");
    return;
  }
  show_node(out, names, table, ms_ty_result(table, ty), budget);
}

static void show_optional(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy inner,
                          int *budget) {
  const bool wrap = ms_ty_kind(table, inner) == MS_TY_FUNCTION;
  ms_strbuild_append_text(out, wrap ? "(" : "");
  show_node(out, names, table, inner, budget);
  ms_strbuild_append_text(out, wrap ? ")?" : "?");
}

static void show_node(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty, int *budget) {
  if (*budget == 0) {
    ms_strbuild_append_utf8(out, 0x2026);
    return;
  }
  (*budget)--;
  if (ms_ty_kind(table, ty) == MS_TY_INVALID) {
    ms_strbuild_append_text(out, "<invalid>");
    return;
  }
  if (ms_ty_kind(table, ty) == MS_TY_FUNCTION) {
    show_function(out, names, table, ty, budget);
    return;
  }
  const MsTy *args = ms_ty_args(table, ty);
  const size_t count = ms_ty_arg_count(table, ty);
  if (ms_ty_is(table, ty, MS_BUILTIN_Optional) && count == 1) {
    show_optional(out, names, table, args[0], budget);
    return;
  }
  ms_strbuild_append(out, ms_names_span(names, ms_ty_row(table, ty)->name));
  if (count == 0) {
    return;
  }
  ms_strbuild_append_byte(out, '[');
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_append_text(out, index > 0 ? ", " : "");
    show_node(out, names, table, args[index], budget);
  }
  ms_strbuild_append_byte(out, ']');
}

void ms_ty_show(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty) {
  int budget = SHOW_NODE_BUDGET;
  show_node(out, names, table, ty, &budget);
}

typedef struct Binding {
  const MsTy *vars;
  const MsTy *args;
  size_t count;
} Binding;

static MsTy substitute(MsTyTable *table, MsTy ty, const Binding *binding);

/* Substitutes each of `count` types at `source` (a pool offset) into scratch; true when any changed. */
static bool subst_args(MsTyTable *table, size_t at, size_t count, const Binding *binding, size_t *mark) {
  *mark = table->scratch.len;
  bool changed = false;
  for (size_t index = 0; index < count; index++) {
    const MsTy before = table->args_pool.ptr[at + index];
    const MsTy after = substitute(table, before, binding);
    ms_ty_list_push(&table->scratch, after);
    changed = changed || after != before;
  }
  return changed;
}

static MsTy rebuild(MsTyTable *table, MsTy ty, const Binding *binding) {
  const MsTyRow row = *ms_ty_row(table, ty);
  size_t arg_mark = 0;
  bool changed = subst_args(table, row.args_at, row.arg_count, binding, &arg_mark);
  const size_t param_mark = table->param_scratch.len;
  for (uint32_t index = 0; index < row.param_count; index++) {
    MsTyParam param = table->params_pool.ptr[row.params_at + index];
    const MsTy after = substitute(table, param.ty, binding);
    changed = changed || after != param.ty;
    param.ty = after;
    ms_ty_param_list_push(&table->param_scratch, param);
  }
  const MsTy result = substitute(table, row.result, binding);
  MsTy out = ty;
  if (changed || result != row.result) {
    const MsTyDesc desc = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind,
                           .builtin = (MsBuiltin)row.builtin, .def = row.def,
                           .args = table->scratch.ptr + arg_mark, .arg_count = row.arg_count,
                           .params = table->param_scratch.ptr + param_mark, .param_count = row.param_count,
                           .result = result};
    out = ms_ty_intern(table, &desc);
  }
  ms_ty_param_list_truncate(&table->param_scratch, param_mark);
  ms_ty_list_truncate(&table->scratch, arg_mark);
  return out;
}

static MsTy substitute(MsTyTable *table, MsTy ty, const Binding *binding) {
  if (!ms_ty_has_variable(table, ty)) {
    return ty;
  }
  for (size_t index = 0; index < binding->count; index++) {
    if (binding->vars[index] == ty) {
      return binding->args[index];
    }
  }
  return rebuild(table, ty, binding);
}

MsTy ms_ty_subst(MsTyTable *table, MsTy ty, const MsTy *vars, const MsTy *args, size_t count) {
  const Binding binding = {.vars = vars, .args = args, .count = count};
  return substitute(table, ty, &binding);
}
