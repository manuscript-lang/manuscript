/* compiler/lower/lower_types.c: checked types to MIR types. A type with variables is first rewritten by the
 * substitution of the instance being lowered, so MIR never sees a variable. */
#include "compiler/lower/lower_internal.h"

static MsTy apply_subst(Lower *cx, const LowerSubst *subst, MsTy ty) {
  if (subst == NULL || subst->count == 0 || !ms_ty_has_variable(&cx->program->types, ty)) {
    return ty;
  }
  return ms_ty_subst(&cx->program->types, ty, subst->vars, subst->args, subst->count);
}

void lower_type_text(Lower *cx, const LowerSubst *subst, MsTy ty, MsStrBuild *out) {
  ms_ty_show(out, cx->program->names, &cx->program->types, apply_subst(cx, subst, ty));
}

/* The name MIR gives a nominal type: its display text with the type arguments (`Box[Int]`). */
static MsName mir_type_name(Lower *cx, MsTy ty) {
  MsStrBuild text = ms_strbuild_new();
  ms_ty_show(&text, cx->program->names, &cx->program->types, ty);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

static MirTy primitive(MsBuiltin builtin) {
  switch (builtin) {
  case MS_BUILTIN_Int:
  case MS_BUILTIN_Int64:
    return MIR_INT;
  case MS_BUILTIN_Int8: return MIR_INT8;
  case MS_BUILTIN_Int16: return MIR_INT16;
  case MS_BUILTIN_Int32: return MIR_INT32;
  case MS_BUILTIN_UInt8: return MIR_UINT8;
  case MS_BUILTIN_UInt16: return MIR_UINT16;
  case MS_BUILTIN_UInt32: return MIR_UINT32;
  case MS_BUILTIN_UInt64: return MIR_UINT64;
  case MS_BUILTIN_Float:
  case MS_BUILTIN_Float64:
    return MIR_FLOAT;
  case MS_BUILTIN_Float32: return MIR_FLOAT32;
  case MS_BUILTIN_Bool: return MIR_BOOL;
  case MS_BUILTIN_String: return MIR_STR;
  case MS_BUILTIN_Bytes: return MIR_BYTES;
  default:
    return MIR_VOID;
  }
}

static MirTy lower_args_type(Lower *cx, MsTy ty, MirTy elem_of(MirModule *, MirTy)) {
  const MsTy *args = ms_ty_args(&cx->program->types, ty);
  return elem_of(cx->module, lower_type(cx, NULL, args[0]));
}

static MirTy lower_function(Lower *cx, MsTy ty) {
  const MsTyTable *table = &cx->program->types;
  const size_t count = ms_ty_param_count(table, ty);
  const MsTyParam *params = ms_ty_params(table, ty);
  MirTy *tys = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirTy, count + 1);
  uint64_t owned = 0;
  for (size_t index = 0; index < count; index++) {
    const bool by_address = (params[index].flags & MS_PARAM_VAR) != 0 && index < 32;
    /* A parameter a function value may leave out crosses it as an optional. */
    const MirTy held = by_address ? MIR_PTR : lower_type(cx, NULL, params[index].ty);
    tys[index] = (params[index].flags & MS_PARAM_LIFTED) != 0 && !by_address ? mir_ty_opt(cx->module, held) : held;
    owned |= (params[index].flags & MS_PARAM_MOVE) != 0 && index < 32 ? UINT64_C(1) << index : 0;
    owned |= by_address ? UINT64_C(1) << (MIR_FN_VAR_SHIFT + index) : 0;
  }
  return mir_ty_fn(cx->module, tys, (uint32_t)count, lower_type(cx, NULL, ms_ty_result(table, ty)), owned);
}

/* The MIR fields for the checker's fields of a nominal type whose variables the arguments of `ty` replace. */
static MirField *lower_fields(Lower *cx, MsTy ty, const MsDef *def, const MsTyParam *fields, size_t count) {
  MirField *out = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirField, count + 1);
  const MsTy *args = ms_ty_args(&cx->program->types, ty);
  const LowerSubst subst = {def->variables.ptr, args, def->variables.len < ms_ty_arg_count(&cx->program->types, ty)
                                                         ? def->variables.len
                                                         : ms_ty_arg_count(&cx->program->types, ty)};
  for (size_t index = 0; index < count; index++) {
    out[index] = (MirField){mir_name(cx->module, ms_names_span(cx->program->names, fields[index].name)),
                            lower_type(cx, &subst, fields[index].ty), 0};
  }
  return out;
}

static MirTy lower_record(Lower *cx, MsTy ty) {
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, ty)->def);
  const uint32_t id = mir_add_type(cx->module, mir_type_name(cx, ty));
  const MirTy result = mir_ty_type(cx->module, id);
  lower_ty_map_put(&cx->types, ty, result); /* a recursive field finds the type under construction */
  MirField *fields = lower_fields(cx, ty, def, def->fields.ptr, def->fields.len);
  const MsDecl *decl = cx->program->symbols.ptr[def->symbol].decl;
  if (decl != NULL && decl->kind == MS_D_TYPE && decl->u.type.fields.len == def->fields.len) {
    const size_t nargs = ms_ty_arg_count(&cx->program->types, ty);
    const LowerSubst subst = {def->variables.ptr, ms_ty_args(&cx->program->types, ty),
                              def->variables.len < nargs ? def->variables.len : nargs};
    for (size_t index = 0; index < def->fields.len; index++) {
      const MsExpr *value = decl->u.type.fields.ptr[index]->def;
      if (value != NULL) {
        fields[index].default_fn1 =
            1 + lower_field_default(cx, cx->program->symbols.ptr[def->symbol].module, value, fields[index].ty, result, &subst);
      }
    }
  }
  cx->module->type_defs.ptr[id].fields = fields;
  cx->module->type_defs.ptr[id].nfields = (uint32_t)def->fields.len;
  return result;
}

static MirTy lower_alt(Lower *cx, MsTy ty) {
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, ty)->def);
  const uint32_t id = mir_add_alt(cx->module, mir_type_name(cx, ty));
  const MirTy result = mir_ty_alt(cx->module, id);
  lower_ty_map_put(&cx->types, ty, result);
  MirCaseDef *cases = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirCaseDef, def->cases.len + 1);
  for (size_t index = 0; index < def->cases.len; index++) {
    const MsTyCase *source = &def->cases.ptr[index];
    cases[index].name = mir_name(cx->module, ms_names_span(cx->program->names, source->name));
    cases[index].fields = lower_fields(cx, ty, def, source->fields.ptr, source->fields.len);
    cases[index].nfields = (uint32_t)source->fields.len;
  }
  MirAltDef *alt = &cx->module->alts.ptr[id];
  alt->cases = cases;
  alt->ncases = (uint32_t)def->cases.len;
  const MsBuiltin builtin = ms_ty_builtin(&cx->program->types, ty);
  alt->std = builtin == MS_BUILTIN_Result ? MSTD_RESULT : MSTD_NONE;
  return result;
}

static MirTy lower_iface(Lower *cx, MsTy ty) {
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, ty)->def);
  const uint32_t id = mir_add_iface(cx->module, mir_type_name(cx, ty));
  const MirTy result = mir_ty_iface(cx->module, id);
  lower_ty_map_put(&cx->types, ty, result);
  const size_t nargs = ms_ty_arg_count(&cx->program->types, ty);
  const LowerSubst subst = {def->variables.ptr, ms_ty_args(&cx->program->types, ty),
                            def->variables.len < nargs ? def->variables.len : nargs};
  MirMethodSig *methods = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirMethodSig, def->operations.len + 1);
  for (size_t index = 0; index < def->operations.len; index++) {
    const MsOperation *operation = &def->operations.ptr[index];
    const MsTy fn = operation->ty;
    const size_t count = ms_ty_param_count(&cx->program->types, fn);
    const MsTyParam *params = ms_ty_params(&cx->program->types, fn);
    methods[index].name = mir_name(cx->module, ms_names_span(cx->program->names, operation->name));
    methods[index].params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirTy, count + 1);
    methods[index].nparams = (uint32_t)count;
    for (size_t p = 0; p < count; p++) {
      methods[index].params[p] = lower_type(cx, &subst, params[p].ty);
      methods[index].owned |= (params[p].flags & MS_PARAM_MOVE) != 0 && p < 64 ? UINT64_C(1) << p : 0;
    }
    methods[index].ret = lower_type(cx, &subst, ms_ty_result(&cx->program->types, fn));
  }
  cx->module->ifaces.ptr[id].methods = methods;
  cx->module->ifaces.ptr[id].nmethods = (uint32_t)def->operations.len;
  return result;
}

/* A native type declared `@repr=inline<N>`: a plain record of N/8 words, which the runtime reads and writes by the
 * address of a copy. */
static MirTy lower_inline(Lower *cx, MsTy ty, uint32_t size) {
  const MsTyTable *table = &cx->program->types;
  const uint32_t id = mir_add_type(cx->module, mir_name(cx->module, ms_names_span(cx->program->names, ms_ty_row(table, ty)->name)));
  const uint32_t words = size / 8;
  MirField *fields = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirField, (size_t)words + 1);
  for (uint32_t at = 0; at < words; at++) {
    fields[at] = (MirField){mir_name(cx->module, ms_span_of_text("word")), MIR_INT, 0};
  }
  cx->module->type_defs.ptr[id].fields = fields;
  cx->module->type_defs.ptr[id].nfields = words;
  cx->module->type_defs.ptr[id].native = true;
  return mir_ty_type(cx->module, id);
}

static MirTy lower_native(Lower *cx, MsTy ty) {
  const MsTyTable *table = &cx->program->types;
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(table, ty)->def);
  if (def->repr == MS_REPR_BYTES_BUFFER) {
    return MIR_BYTES;
  }
  if (def->repr == MS_REPR_INLINE) {
    return lower_inline(cx, ty, def->repr_size);
  }
  const size_t count = ms_ty_arg_count(table, ty);
  MirTy *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirTy, count + 1);
  for (size_t index = 0; index < count; index++) {
    args[index] = lower_type(cx, NULL, ms_ty_args(table, ty)[index]);
  }
  return mir_ty_obj(cx->module, mir_name(cx->module, ms_names_span(cx->program->names, ms_ty_row(table, ty)->name)),
                    args, (uint32_t)count);
}

static MirTy lower_standard(Lower *cx, MsTy ty, MsBuiltin builtin) {
  switch (builtin) {
  case MS_BUILTIN_Optional:
    return lower_args_type(cx, ty, mir_ty_opt);
  case MS_BUILTIN_List:
    return lower_args_type(cx, ty, mir_ty_list);
  case MS_BUILTIN_Bytes:
    return MIR_BYTES;
  default:
    return lower_native(cx, ty);
  }
}

static MirTy lower_by_kind(Lower *cx, MsTy ty) {
  const MsTyTable *table = &cx->program->types;
  const MsBuiltin builtin = ms_ty_builtin(table, ty);
  switch (ms_ty_kind(table, ty)) {
  case MS_TY_PRIMITIVE:
    return primitive(builtin);
  case MS_TY_TYPE:
    return builtin == MS_BUILTIN_List ? lower_standard(cx, ty, builtin) : lower_record(cx, ty);
  case MS_TY_ALTERNATIVE:
    return builtin == MS_BUILTIN_Optional ? lower_standard(cx, ty, builtin) : lower_alt(cx, ty);
  case MS_TY_CONTRACT:
    return lower_iface(cx, ty);
  case MS_TY_FUNCTION:
    return lower_function(cx, ty);
  case MS_TY_NATIVE:
    return lower_standard(cx, ty, builtin);
  case MS_TY_VARIABLE:
  case MS_TY_INVALID:
  case MS_TY_INFERRED:
    break;
  }
  MsStrBuild shown = ms_strbuild_new();
  ms_ty_show(&shown, cx->program->names, &cx->program->types, ty);
  const MsSpan text = ms_strbuild_span(&shown);
  (void)lower_fail(cx, "a type with no MIR form reached lowering: %.*s (kind %s)", (int)text.len,
                   (const char *)text.ptr, ms_ty_kind_name(ms_ty_kind(&cx->program->types, ty)));
  ms_strbuild_free(&shown);
  return MIR_VOID;
}

MirTy lower_type(Lower *cx, const LowerSubst *subst, MsTy ty) {
  const MsTy concrete = apply_subst(cx, subst, ty);
  const uint32_t *known = lower_ty_map_get(&cx->types, concrete);
  if (known != NULL) {
    return *known;
  }
  const MirTy result = lower_by_kind(cx, concrete);
  lower_ty_map_put(&cx->types, concrete, result);
  return result;
}
