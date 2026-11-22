/* compiler/check/implements.c: whether a type satisfies an interface.
 *
 * No declaration names the relationship: a type satisfies an interface when its own methods supply every
 * operation with the interface's exact signature, parameter names and `var`/`move` receiver mode. A type
 * variable satisfies the interfaces it is bounded by, a type set admits its members, and the built-in
 * scalars satisfy Comparable. Equal, Hashable, Clonable and Data are structural properties (properties.c). */
#include "compiler/check/methods.h"

#include "compiler/check/program.h"
#include "compiler/check/properties.h"

/* ---- types ---- */

MsTy ms_check_replace_type(MsTyTable *types, MsTy ty, MsTy from, MsTy to) {
  if (ty == from) {
    return to;
  }
  const MsTyRow row = *ms_ty_row(types, ty);
  if (row.arg_count == 0 && row.param_count == 0 && row.result == MS_TY_NONE) {
    return ty;
  }
  MsTyList args = {0};
  MsTyParamList params = {0};
  bool changed = false;
  for (uint32_t index = 0; index < row.arg_count; index++) {
    const MsTy before = types->args_pool.ptr[row.args_at + index];
    const MsTy after = ms_check_replace_type(types, before, from, to);
    changed = changed || after != before;
    ms_ty_list_push(&args, after);
  }
  for (uint32_t index = 0; index < row.param_count; index++) {
    MsTyParam param = types->params_pool.ptr[row.params_at + index];
    const MsTy after = ms_check_replace_type(types, param.ty, from, to);
    changed = changed || after != param.ty;
    param.ty = after;
    ms_ty_param_list_push(&params, param);
  }
  const MsTy result = row.result == MS_TY_NONE ? MS_TY_NONE : ms_check_replace_type(types, row.result, from, to);
  MsTy out = ty;
  if (changed || result != row.result) {
    const MsTyDesc desc = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind,
                           .builtin = (MsBuiltin)row.builtin, .def = row.def, .args = args.ptr,
                           .arg_count = row.arg_count, .params = params.ptr, .param_count = row.param_count,
                           .result = result};
    out = ms_ty_intern(types, &desc);
  }
  ms_ty_list_free(&args);
  ms_ty_param_list_free(&params);
  return out;
}

/* The definition of an interface type, or NULL for any other type. */
static const MsDef *contract_def(const MsCheckProgram *program, MsTy contract) {
  const MsTyRow *row = ms_ty_row(&program->types, contract);
  return row->kind == MS_TY_CONTRACT && row->def != 0 ? ms_defs_get(&program->defs, row->def) : NULL;
}

const MsOperation *ms_check_find_operation(const MsCheckProgram *program, MsTy contract, MsName name) {
  const MsDef *def = contract_def(program, contract);
  for (size_t index = 0; def != NULL && index < def->operations.len; index++) {
    if (def->operations.ptr[index].name == name) {
      return &def->operations.ptr[index];
    }
  }
  return NULL;
}

/* `ty` as an operation of `contract` sees it on `implementor`: `Self` is the implementor, the interface's type
 * arguments are bound. */
static MsTy bind_contract(MsCheckProgram *program, MsTy contract, MsTy ty, MsTy implementor) {
  const MsDef *def = contract_def(program, contract);
  const MsTy own = program->symbols.ptr[def->symbol].ty;
  const MsTy bound = ms_check_replace_type(&program->types, ty, own, implementor);
  if (def->variables.len != ms_ty_arg_count(&program->types, contract)) {
    return bound;
  }
  return ms_ty_subst(&program->types, bound, def->variables.ptr, ms_ty_args(&program->types, contract),
                     def->variables.len);
}

MsTy ms_check_operation_type(MsCheckProgram *program, MsTy contract, const MsOperation *operation, MsTy implementor) {
  return bind_contract(program, contract, operation->ty, implementor);
}

/* ---- shape ---- */

/* The declaration of an interface operation: the method of the interface's syntax with the operation's node. */
static const MsMethod *operation_method(const MsCheckProgram *program, const MsDef *def, const MsOperation *operation) {
  const MsDecl *decl = program->symbols.ptr[def->symbol].decl;
  for (uint32_t index = 0; decl != NULL && index < decl->u.iface.methods.len; index++) {
    if (decl->u.iface.methods.ptr[index]->id == operation->decl.node) {
      return decl->u.iface.methods.ptr[index];
    }
  }
  return NULL;
}

const MsMethod *ms_check_operation_declaration(const MsCheckProgram *program, MsTy contract, const MsOperation *operation) {
  const MsDef *def = contract_def(program, contract);
  return def == NULL ? NULL : operation_method(program, def, operation);
}

/* `(name: Type, ...) Result`, with `T!` for a Result over Error. */
static void append_signature(const MsCheckProgram *program, MsTy ty, MsStrBuild *out) {
  const MsTyTable *types = &program->types;
  ms_strbuild_append_byte(out, '(');
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    const MsTyParam *param = &ms_ty_params(types, ty)[index];
    ms_strbuild_append_text(out, index > 0 ? ", " : "");
    ms_strbuild_append_text(out, (param->flags & MS_PARAM_MOVE) != 0 ? "move " : "");
    ms_strbuild_append_text(out, (param->flags & MS_PARAM_VAR) != 0 ? "var " : "");
    ms_strbuild_append(out, ms_names_span(program->names, param->name));
    ms_strbuild_append_text(out, ": ");
    ms_ty_show(out, program->names, types, param->ty);
  }
  ms_strbuild_append_text(out, ") ");
  const MsTy result = ms_ty_result(types, ty);
  if (ms_ty_is(types, result, MS_BUILTIN_Result) && ms_ty_arg_count(types, result) == 2 &&
      ms_ty_is(types, ms_ty_args(types, result)[1], MS_BUILTIN_Error)) {
    ms_ty_show(out, program->names, types, ms_ty_args(types, result)[0]);
    ms_strbuild_append_byte(out, '!');
    return;
  }
  ms_ty_show(out, program->names, types, result);
}

static void say(MsStrBuild *why, MsName name, const MsCheckProgram *program, const char *text) {
  ms_strbuild_append(why, ms_names_span(program->names, name));
  ms_strbuild_append_text(why, text);
}

static bool same_parameter_names(const MsMethod *left, const MsMethod *right) {
  if (left->func.params.len != right->func.params.len) {
    return true; /* the signatures differ in count: the type comparison reports it */
  }
  for (uint32_t index = 0; index < left->func.params.len; index++) {
    if (left->func.params.ptr[index]->name != right->func.params.ptr[index]->name) {
      return false;
    }
  }
  return true;
}

/* Why the method `own` does not meet the operation's declaration; false with the reason appended. */
static bool matches_declaration(const MsCheckProgram *program, MsName name, const MsMethod *own,
                                const MsMethod *want, MsStrBuild *why) {
  if (own == NULL || want == NULL) {
    say(why, name, program, " has no declaration to compare");
    return false;
  }
  if (own->consuming != want->consuming) {
    say(why, name, program,
        want->consuming ? " must take its receiver with `move`, as the interface does"
                        : " must not take its receiver with `move`; the interface borrows it");
    return false;
  }
  if (!same_parameter_names(own, want)) {
    say(why, name, program, " must name its parameters like the interface");
    return false;
  }
  if (own->mutating && !want->mutating) {
    say(why, name, program, " must not be `var fn`");
    return false;
  }
  return true;
}

/* The methods of `receiver` that are its own and named `name`. */
static void own_methods(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out) {
  MsMethodMatchList found = {0};
  ms_check_find_method(program, receiver, name, &found);
  for (size_t index = 0; index < found.len; index++) {
    if (found.ptr[index].entry != NULL) {
      ms_method_match_list_push(out, found.ptr[index]);
    }
  }
  ms_method_match_list_free(&found);
}

/* Whether the method's own type parameters carry the operation's bounds, position by position. */
static bool bounds_match(MsCheckProgram *program, MsTy receiver, MsTy contract, const MsOperation *operation,
                         const MsMethodEntry *entry) {
  const MsTy *own = entry->variables.ptr + entry->shared;
  for (size_t index = 0; index < operation->variables.len; index++) {
    const MsTyVariable *want = ms_ty_variable(&program->types, operation->variables.ptr[index]);
    const MsTyVariable *have = ms_ty_variable(&program->types, own[index]);
    if (want->bounds.len != have->bounds.len) {
      return false;
    }
    for (size_t at = 0; at < want->bounds.len; at++) {
      MsTy bound = bind_contract(program, contract, want->bounds.ptr[at], receiver);
      bound = ms_ty_subst(&program->types, bound, operation->variables.ptr, own, operation->variables.len);
      if (bound != have->bounds.ptr[at]) {
        return false;
      }
    }
  }
  return true;
}

/* Whether the one operation is met; false with the reason appended. */
static bool operation_met(MsCheckProgram *program, MsTy receiver, MsTy contract, const MsDef *def,
                          const MsOperation *operation, MsStrBuild *why) {
  MsMethodMatchList own = {0};
  own_methods(program, receiver, operation->name, &own);
  const MsMethod *declared = operation_method(program, def, operation);
  const size_t declared_count = operation->variables.len;
  const MsMethodMatch *chosen = NULL;
  bool met = false;
  if (own.len == 0 || (declared_count > 0 && own.len != 1)) {
    say(why, operation->name, program, " is missing");
  } else if (declared_count > 0 && own.ptr[0].entry->variables.len - own.ptr[0].entry->shared != declared_count) {
    say(why, operation->name, program, " must declare the same type parameters as the interface");
  } else if (declared_count > 0 && !bounds_match(program, receiver, contract, operation, own.ptr[0].entry)) {
    say(why, operation->name, program, " must bound its type parameters like the interface");
  } else {
    MsTy wanted = ms_check_operation_type(program, contract, operation, receiver);
    if (declared_count > 0) { /* the operation's variables are met by the method's, position by position */
      wanted = ms_ty_subst(&program->types, wanted, operation->variables.ptr,
                           own.ptr[0].entry->variables.ptr + own.ptr[0].entry->shared, declared_count);
    }
    for (size_t index = 0; index < own.len && chosen == NULL; index++) {
      if (own.ptr[index].ty == wanted) {
        chosen = &own.ptr[index]; /* methods of one name may differ by their receiver's bounds: the exact one wins */
      }
    }
    chosen = chosen != NULL ? chosen : (own.len == 1 ? &own.ptr[0] : NULL);
    if (chosen == NULL) {
      say(why, operation->name, program, " is missing");
    } else if (chosen->ty != wanted) {
      say(why, operation->name, program, " must be declared as fn ");
      ms_strbuild_append(why, ms_names_span(program->names, operation->name));
      append_signature(program, wanted, why);
    } else {
      met = matches_declaration(program, operation->name, chosen->entry->source, declared, why);
    }
  }
  ms_method_match_list_free(&own);
  return met;
}

bool ms_check_shape_gap(MsCheckProgram *program, MsTy receiver, MsTy contract, MsStrBuild *why) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  const MsDef *def = contract_def(program, contract);
  if ((kind != MS_TY_TYPE && kind != MS_TY_ALTERNATIVE && kind != MS_TY_NATIVE && kind != MS_TY_PRIMITIVE) ||
      def == NULL || def->operations.len == 0 || ms_ty_arg_count(&program->types, contract) != def->variables.len) {
    return false; /* shape does not apply */
  }
  for (size_t index = 0; index < def->operations.len; index++) {
    if (!operation_met(program, receiver, contract, def, &def->operations.ptr[index], why)) {
      return false;
    }
  }
  return true;
}

bool ms_check_shape_optional(MsCheckProgram *program, MsTy receiver, MsTy contract) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  const MsDef *def = contract_def(program, contract);
  if ((kind != MS_TY_TYPE && kind != MS_TY_ALTERNATIVE && kind != MS_TY_NATIVE && kind != MS_TY_PRIMITIVE) || def == NULL) {
    return false;
  }
  MsStrBuild why = ms_strbuild_new();
  bool met = true;
  for (size_t index = 0; met && index < def->operations.len; index++) {
    MsMethodMatchList own = {0};
    own_methods(program, receiver, def->operations.ptr[index].name, &own);
    const bool declared = own.len > 0;
    ms_method_match_list_free(&own);
    met = !declared || operation_met(program, receiver, contract, def, &def->operations.ptr[index], &why);
  }
  ms_strbuild_free(&why);
  return met;
}

/* ---- implements ---- */

static bool type_set_admits(MsTyTable *types, MsTy ty, MsTy set) {
  const MsTy *members = ms_ty_args(types, set);
  const size_t count = ms_ty_arg_count(types, set);
  if (ms_ty_kind(types, ty) == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(types, ty);
    for (size_t index = 0; index < record->bounds.len; index++) {
      const MsTy bound = record->bounds.ptr[index];
      bool all = ms_ty_is(types, bound, MS_BUILTIN_TypeSet) && ms_ty_arg_count(types, bound) > 0;
      for (size_t at = 0; all && at < ms_ty_arg_count(types, bound); at++) {
        bool found = false;
        for (size_t member = 0; member < count; member++) {
          found = found || members[member] == ms_ty_args(types, bound)[at];
        }
        all = found;
      }
      if (all) {
        return true;
      }
    }
    return false;
  }
  for (size_t index = 0; index < count; index++) {
    if (members[index] == ty) {
      return true;
    }
  }
  return false;
}

/* The standard types whose native comparison satisfies Comparable. */
static bool builtin_comparable(const MsTyTable *types, MsTy ty) {
  const MsBuiltin builtin = ms_ty_builtin(types, ty);
  return ms_builtin_is_int(builtin) || ms_builtin_is_float(builtin) || builtin == MS_BUILTIN_String ||
         builtin == MS_BUILTIN_Decimal || builtin == MS_BUILTIN_BigInt || builtin == MS_BUILTIN_Timestamp;
}

bool ms_check_implements(MsCheckProgram *program, MsTy receiver, MsTy contract) {
  const MsTyTable *types = &program->types;
  if (ms_ty_row(types, receiver)->id == ms_ty_row(types, contract)->id) {
    return receiver == contract;
  }
  const MsBuiltin builtin = ms_ty_builtin(types, contract);
  MsProperty property = MS_PROPERTY_EQUAL;
  if (ms_property_of_builtin(builtin, &property)) {
    return ms_check_property(program, receiver, property);
  }
  if (builtin == MS_BUILTIN_TypeSet) {
    return type_set_admits(&program->types, receiver, contract);
  }
  if (ms_ty_kind(types, receiver) == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(&program->types, receiver);
    for (size_t index = 0; index < record->bounds.len; index++) {
      if (record->bounds.ptr[index] == contract) {
        return true;
      }
    }
    return false;
  }
  if (builtin == MS_BUILTIN_Comparable && builtin_comparable(types, receiver)) {
    return true;
  }
  MsStrBuild why = ms_strbuild_new();
  const bool met = ms_check_shape_gap(program, receiver, contract, &why);
  ms_strbuild_free(&why);
  return met;
}
