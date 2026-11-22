/* compiler/lower/lower_conv.c: conversions the checker recorded on an expression: a value seen as an interface it
 * implements (a vtable of the type's methods, made on first use), and the other conversions. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

static const MsConversion *find_conversion(const MsFacts *facts, MsNode node) {
  size_t lo = 0;
  size_t hi = facts->conversions.len;
  while (lo < hi) {
    const size_t mid = lo + (hi - lo) / 2;
    if (facts->conversions.ptr[mid].node < node) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < facts->conversions.len && facts->conversions.ptr[lo].node == node ? &facts->conversions.ptr[lo]
                                                                                 : NULL;
}

/* The method table entry of the method an interface operation resolves to for `receiver`. */
static const MsMethodEntry *resolve_operation(Lower *cx, MsTy receiver, MsName name) {
  MsMethodMatchList matches = {0};
  ms_check_find_method(cx->program, receiver, name, &matches);
  const MsMethodEntry *found = NULL;
  for (size_t index = 0; index < matches.len && found == NULL; index++) {
    found = matches.ptr[index].entry;
  }
  ms_method_match_list_free(&matches);
  return found;
}

/* Instantiates `entry` for `receiver`: its variables are bound by matching the receiver form. */
static uint32_t method_function(Lower *cx, const MsMethodEntry *entry, MsTy receiver) {
  MsTy bound[16] = {0};
  const size_t count = entry->variables.len;
  if (count > 16 || !ms_check_unify(&cx->program->types, entry->receiver, receiver, entry->variables.ptr, count, bound)) {
    (void)lower_fail(cx, "an interface method does not fit its receiver type");
    return MIR_NONE;
  }
  const LowerTarget target = {entry->module, entry->source->id, &entry->source->func, entry->name, entry->ty,
                              {NULL, 0}, entry->variables.ptr, (uint32_t)count};
  return lower_instance(cx, &target, bound, (uint32_t)count, NULL);
}

static void vtable_name(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface, MsStrBuild *out) {
  ms_strbuild_append_text(out, "vtable ");
  lower_type_text(cx, subst, receiver, out);
  ms_strbuild_append_text(out, " as ");
  lower_type_text(cx, subst, iface, out);
}

static uint32_t build_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface, MsName name) {
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, iface)->def);
  uint32_t *methods = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint32_t, def->operations.len + 1);
  for (size_t index = 0; index < def->operations.len; index++) {
    const MsMethodEntry *entry = resolve_operation(cx, receiver, def->operations.ptr[index].name);
    methods[index] = entry != NULL ? method_function(cx, entry, receiver) : MIR_NONE;
    if (methods[index] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  const MirTy iface_ty = lower_type(cx, subst, iface);
  const MirVtable vtable = {name, mir_ty_data(cx->module, iface_ty)->id, methods, (uint32_t)def->operations.len,
                            lower_type(cx, subst, receiver)};
  return mir_add_vtable(cx->module, &vtable);
}

uint32_t lower_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface) {
  MsStrBuild key = ms_strbuild_new();
  vtable_name(cx, subst, receiver, iface, &key);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&key));
  const MsName id = ms_names_intern(&cx->vtable_keys, ms_strbuild_span(&key));
  ms_strbuild_free(&key);
  if (id < cx->vtables.len) {
    return cx->vtables.ptr[id];
  }
  /* Recorded before the methods are lowered, so a method that builds the same view finds it. */
  mir_idlist_push(&cx->vtables, MIR_NONE);
  const uint32_t vtable = build_vtable(cx, subst, receiver, iface, name);
  cx->vtables.ptr[id] = vtable;
  return vtable;
}

static MirValue view_as_interface(LowerFn *fn, const MsConversion *conversion, MirValue value) {
  const uint32_t vtable = lower_vtable(fn->cx, &fn->subst, conversion->from, conversion->to);
  if (vtable == MIR_NONE) {
    fn->failed = true;
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_VTABLE, .a = vtable};
  return fn_emit(fn, MOP_IfaceNew, &value, 1, imm, fn_type(fn, conversion->to));
}

MirValue fn_convert(LowerFn *fn, const MsExpr *expr, MirValue value) {
  const MsConversion *conversion = find_conversion(fn->facts, expr->id);
  if (conversion == NULL || value == MIR_NONE) {
    return value;
  }
  if (conversion->kind == MS_CONV_INTERFACE_VIEW) {
    return view_as_interface(fn, conversion, value);
  }
  if (conversion->kind == MS_CONV_OPTIONAL_WRAP) {
    const MirImm none = {0};
    return fn_emit(fn, MOP_OptSome, &value, 1, none, fn_type(fn, conversion->to));
  }
  (void)fn_fail(fn, "this conversion (kind %d) is not lowered yet", (int)conversion->kind);
  return MIR_NONE;
}
