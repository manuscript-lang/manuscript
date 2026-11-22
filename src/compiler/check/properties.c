/* compiler/check/properties.c: Equal, Hashable, Clonable and Data from a type's shape (see properties.h). */
#include "compiler/check/properties.h"

#include "compiler/check/program.h"
#include "compiler/project/project.h"

bool ms_property_of_builtin(MsBuiltin builtin, MsProperty *out) {
  switch (builtin) {
  case MS_BUILTIN_Equal:
    *out = MS_PROPERTY_EQUAL;
    return true;
  case MS_BUILTIN_Hashable:
    *out = MS_PROPERTY_HASHABLE;
    return true;
  case MS_BUILTIN_Clonable:
    *out = MS_PROPERTY_CLONABLE;
    return true;
  case MS_BUILTIN_Data:
    *out = MS_PROPERTY_DATA;
    return true;
  default:
    return false;
  }
}

void ms_property_memo_free(MsPropertyMemo *memo) {
  ms_property_key_list_free(&memo->active);
  ms_property_key_list_free(&memo->done);
}

/* ---- the parts of a type ---- */

static const MsDef *def_of(const MsCheckProgram *program, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&program->types, ty);
  const bool nominal = row->kind == MS_TY_TYPE || row->kind == MS_TY_ALTERNATIVE || row->kind == MS_TY_NATIVE;
  return nominal && row->def != 0 ? ms_defs_get(&program->defs, row->def) : NULL;
}

/* `field` as the type `ty` has it: the definition's variables replaced by `ty`'s arguments. */
static MsTy part_type(MsCheckProgram *program, MsTy ty, const MsDef *def, MsTy field) {
  if (def->variables.len == 0 || def->variables.len != ms_ty_arg_count(&program->types, ty)) {
    return field;
  }
  return ms_ty_subst(&program->types, field, def->variables.ptr, ms_ty_args(&program->types, ty),
                     def->variables.len);
}

/* The declaration of `ty`, or NULL. */
static const MsDecl *decl_of(const MsCheckProgram *program, const MsDef *def) {
  return def != NULL ? program->symbols.ptr[def->symbol].decl : NULL;
}

static bool is_opaque(const MsCheckProgram *program, const MsDef *def) {
  const MsDecl *decl = decl_of(program, def);
  if (decl == NULL) {
    return false;
  }
  return (decl->kind == MS_D_TYPE && decl->u.type.opaque) || (decl->kind == MS_D_ENUM && decl->u.enumeration.opaque);
}

/* Whether a bundled type carries `// ms: <word>` among the comment lines directly above its declaration. */
static bool has_marker(const MsCheckProgram *program, const MsDef *def, const char *word) {
  const MsSymbol *symbol = &program->symbols.ptr[def->symbol];
  const MsSpan file = ms_names_span(program->names, program->modules.ptr[symbol->module].file);
  MsSpan name = {0};
  MsStdSource source = {0};
  if (!ms_span_starts_with(file, ms_span_of_text("@std/")) || !ms_span_slice(file, 5, file.len, &name) ||
      !ms_std_source_find(name, &source) || symbol->decl == NULL) {
    return false;
  }
  size_t end = symbol->decl->pos.offset < source.text.len ? symbol->decl->pos.offset : source.text.len;
  while (end > 0 && source.text.ptr[end - 1] != '\n') {
    end--;
  }
  while (end > 0) {
    size_t start = end - 1;
    while (start > 0 && source.text.ptr[start - 1] != '\n') {
      start--;
    }
    MsSpan line = ms_span_of(source.text.ptr + start, end - 1 - start);
    while (line.len > 0 && (line.ptr[0] == ' ' || line.ptr[0] == '\t')) {
      line = ms_span_of(line.ptr + 1, line.len - 1);
    }
    while (line.len > 0 && (line.ptr[line.len - 1] == ' ' || line.ptr[line.len - 1] == '\r')) {
      line = ms_span_of(line.ptr, line.len - 1);
    }
    if (!ms_span_starts_with(line, ms_span_of_text("//"))) {
      return false;
    }
    MsSpan text = ms_span_of(line.ptr + 2, line.len - 2);
    while (text.len > 0 && text.ptr[0] == ' ') {
      text = ms_span_of(text.ptr + 1, text.len - 1);
    }
    MsStrBuild marker = ms_strbuild_new();
    ms_strbuild_append_text(&marker, "ms: ");
    ms_strbuild_append_text(&marker, word);
    const bool found = ms_span_equal(text, ms_strbuild_span(&marker));
    ms_strbuild_free(&marker);
    if (found) {
      return true;
    }
    end = start;
  }
  return false;
}

/* ---- methods that decide a property ---- */

static MsName name_of(MsCheckProgram *program, const char *text) {
  return ms_names_intern(program->names, ms_span_of_text(text));
}

/* Matches of the method `name` on `ty` that are its own. */
static bool has_own_method(MsCheckProgram *program, MsTy ty, const char *name, size_t params, MsBuiltin result,
                           bool param_is_self) {
  MsMethodMatchList found = {0};
  bool any = false;
  ms_check_find_method(program, ty, name_of(program, name), &found);
  for (size_t index = 0; index < found.len && !any; index++) {
    const MsTy signature = found.ptr[index].ty;
    any = found.ptr[index].entry != NULL && ms_ty_param_count(&program->types, signature) == params &&
          ms_ty_is(&program->types, ms_ty_result(&program->types, signature), result) &&
          (!param_is_self || ms_ty_params(&program->types, signature)[0].ty == ty);
  }
  ms_method_match_list_free(&found);
  return any;
}

static bool has_json_encoder(MsCheckProgram *program, MsTy ty) {
  return has_own_method(program, ty, "to_json", 0, MS_BUILTIN_JsonValue, false);
}

/* A `close` that takes nothing and returns Void or `Void!`. */
static bool close_method(MsCheckProgram *program, MsTy ty) {
  MsMethodMatchList found = {0};
  bool any = false;
  ms_check_find_method(program, ty, name_of(program, "close"), &found);
  for (size_t index = 0; index < found.len && !any; index++) {
    const MsTy signature = found.ptr[index].ty;
    const MsTy result = ms_ty_result(&program->types, signature);
    any = ms_ty_param_count(&program->types, signature) == 0 && ms_ty_is(&program->types, result, MS_BUILTIN_Result) &&
          ms_ty_arg_count(&program->types, result) == 2 &&
          ms_ty_is(&program->types, ms_ty_args(&program->types, result)[0], MS_BUILTIN_Void) &&
          ms_ty_is(&program->types, ms_ty_args(&program->types, result)[1], MS_BUILTIN_Error);
  }
  ms_method_match_list_free(&found);
  return any;
}

bool ms_check_closeable(MsCheckProgram *program, MsTy ty) {
  const MsTyKind kind = ms_ty_kind(&program->types, ty);
  if (kind == MS_TY_CONTRACT || kind == MS_TY_VARIABLE) {
    return close_method(program, ty);
  }
  if (program->properties.closeable == MS_TY_NONE) {
    for (MsSymbolId id = 1; id < program->symbols.len; id++) {
      if (program->symbols.ptr[id].kind == MS_SYMBOL_TYPE &&
          ms_ty_is(&program->types, program->symbols.ptr[id].ty, MS_BUILTIN_Closeable)) {
        program->properties.closeable = program->symbols.ptr[id].ty;
        break;
      }
    }
  }
  return program->properties.closeable != MS_TY_NONE && ms_check_implements(program, ty, program->properties.closeable);
}

/* Whether `ty` is, or holds, a closeable value anywhere in its arguments, fields or cases. */
static bool holds_resource(MsCheckProgram *program, MsTy ty, MsTyList *seen) {
  for (size_t index = 0; index < seen->len; index++) {
    if (seen->ptr[index] == ty) {
      return false;
    }
  }
  ms_ty_list_push(seen, ty);
  bool found = ms_check_closeable(program, ty);
  for (size_t index = 0; !found && index < ms_ty_arg_count(&program->types, ty); index++) {
    found = holds_resource(program, ms_ty_args(&program->types, ty)[index], seen);
  }
  const MsDef *def = def_of(program, ty);
  for (size_t index = 0; !found && def != NULL && index < def->fields.len; index++) {
    found = holds_resource(program, part_type(program, ty, def, def->fields.ptr[index].ty), seen);
  }
  for (size_t index = 0; !found && def != NULL && index < def->cases.len; index++) {
    for (size_t at = 0; !found && at < def->cases.ptr[index].fields.len; at++) {
      found = holds_resource(program, part_type(program, ty, def, def->cases.ptr[index].fields.ptr[at].ty), seen);
    }
  }
  return found;
}

static bool holds_resource_anywhere(MsCheckProgram *program, MsTy ty) {
  MsTyList seen = {0};
  const bool found = holds_resource(program, ty, &seen);
  ms_ty_list_free(&seen);
  return found;
}

bool ms_check_holds_resource(MsCheckProgram *program, MsTy ty) {
  return holds_resource_anywhere(program, ty);
}

const MsDef *ms_check_def_of(const MsCheckProgram *program, MsTy ty) {
  return def_of(program, ty);
}

MsTy ms_check_part_type(MsCheckProgram *program, MsTy ty, const MsDef *def, MsTy field) {
  return part_type(program, ty, def, field);
}

/* ---- Data ---- */

static bool blocked(MsDataReason why, MsTy ty, MsDataReason *reason, MsTy *part) {
  *reason = why;
  *part = ty;
  return true;
}

static bool data_walk(MsCheckProgram *program, MsTy ty, MsStrBuild *path, MsTyList *visiting, MsDataReason *reason,
                      MsTy *part);

/* Walks one field: its name joins the path while it is searched. */
static bool data_field(MsCheckProgram *program, MsTy owner, const MsDef *def, const MsTyParam *field, MsStrBuild *path,
                       MsTyList *visiting, MsDataReason *reason, MsTy *part) {
  const size_t mark = ms_strbuild_length(path);
  if (mark > 0) {
    ms_strbuild_append_byte(path, '.');
  }
  ms_strbuild_append(path, ms_names_span(program->names, field->name));
  if (data_walk(program, part_type(program, owner, def, field->ty), path, visiting, reason, part)) {
    return true;
  }
  path->bytes.len = mark;
  return false;
}

static bool data_walk(MsCheckProgram *program, MsTy ty, MsStrBuild *path, MsTyList *visiting, MsDataReason *reason,
                      MsTy *part) {
  const MsTyTable *types = &program->types;
  if (ms_ty_is_invalid(types, ty) || ty == MS_TY_NONE) {
    return false;
  }
  switch (ms_ty_kind(types, ty)) {
  case MS_TY_VARIABLE: {
    const MsTyVariable *record = ms_ty_variable(&program->types, ty);
    for (size_t index = 0; index < record->bounds.len; index++) {
      if (ms_ty_is(types, record->bounds.ptr[index], MS_BUILTIN_Data)) {
        return false;
      }
    }
    return blocked(MS_DATA_UNBOUNDED, ty, reason, part);
  }
  case MS_TY_PRIMITIVE:
    return ms_ty_is(types, ty, MS_BUILTIN_Never) ? blocked(MS_DATA_NEVER, ty, reason, part) : false;
  case MS_TY_FUNCTION:
    return blocked(MS_DATA_FUNCTION, ty, reason, part);
  case MS_TY_CONTRACT:
    return blocked(MS_DATA_INTERFACE, ty, reason, part);
  default:
    break;
  }
  const MsTy *args = ms_ty_args(types, ty);
  const size_t count = ms_ty_arg_count(types, ty);
  if (ms_ty_is(types, ty, MS_BUILTIN_List)) {
    return count > 0 && data_walk(program, args[0], path, visiting, reason, part);
  }
  if (ms_ty_is(types, ty, MS_BUILTIN_Map) && count > 0 && ms_ty_is(types, args[0], MS_BUILTIN_String)) {
    return count > 1 && data_walk(program, args[1], path, visiting, reason, part);
  }
  if (ms_ty_is(types, ty, MS_BUILTIN_Map) || ms_ty_is(types, ty, MS_BUILTIN_Set)) {
    return blocked(MS_DATA_COLLECTION, ty, reason, part);
  }
  const MsDef *def = def_of(program, ty);
  if (ms_ty_kind(types, ty) == MS_TY_NATIVE) {
    return def != NULL && has_marker(program, def, "data") ? false : blocked(MS_DATA_HANDLE, ty, reason, part);
  }
  if (is_opaque(program, def)) {
    return blocked(MS_DATA_OPAQUE, ty, reason, part);
  }
  if (ms_check_closeable(program, ty)) {
    return blocked(MS_DATA_RESOURCE, ty, reason, part);
  }
  if ((def != NULL && has_marker(program, def, "data")) || has_json_encoder(program, ty)) {
    return false;
  }
  for (size_t index = 0; index < visiting->len; index++) {
    if (visiting->ptr[index] == ty) {
      return false;
    }
  }
  ms_ty_list_push(visiting, ty);
  bool found = false;
  for (size_t index = 0; def != NULL && !found && index < def->fields.len; index++) {
    found = data_field(program, ty, def, &def->fields.ptr[index], path, visiting, reason, part);
  }
  for (size_t index = 0; def != NULL && !found && index < def->cases.len; index++) {
    for (size_t at = 0; !found && at < def->cases.ptr[index].fields.len; at++) {
      found = data_field(program, ty, def, &def->cases.ptr[index].fields.ptr[at], path, visiting, reason, part);
    }
  }
  ms_ty_list_truncate(visiting, visiting->len - 1);
  return found;
}

bool ms_check_data_blocker(MsCheckProgram *program, MsTy ty, MsStrBuild *path, MsDataReason *reason, MsTy *part) {
  MsTyList visiting = {0};
  const bool found = data_walk(program, ty, path, &visiting, reason, part);
  ms_ty_list_free(&visiting);
  return found;
}

void ms_check_data_message(const MsCheckProgram *program, MsTy ty, MsDataReason reason, MsTy part, MsSpan path,
                           MsStrBuild *out) {
  static const char *const WHAT[] = {"a resource (Closeable)",
                                     "a function",
                                     "an interface value",
                                     "a runtime handle",
                                     "a type parameter with no Data bound",
                                     "a Set or a Map whose key is not a String, which has no portable form",
                                     "Never, which has no value",
                                     "opaque"};
  static const char *const FIX[] = {"send a path or an id and reopen it on the other side",
                                    "send the data the function would compute",
                                    "send the plain data behind it",
                                    "send plain data instead",
                                    NULL,
                                    "send a List, a Map[String, T], or a JsonValue object",
                                    "use Void or a real type",
                                    "return a plain value from the module that declares it"};
  ms_ty_show(out, program->names, &program->types, ty);
  ms_strbuild_append_text(out, " does not satisfy Data; ");
  if (path.len > 0) {
    ms_strbuild_append_text(out, "field ");
    ms_strbuild_append(out, path);
    ms_strbuild_append_text(out, " is ");
    ms_ty_show(out, program->names, &program->types, part);
    ms_strbuild_append_text(out, ", ");
  } else {
    ms_strbuild_append_text(out, "it is ");
  }
  ms_strbuild_append_text(out, WHAT[reason]);
  ms_strbuild_append_text(out, "; ");
  if (FIX[reason] != NULL) {
    ms_strbuild_append_text(out, FIX[reason]);
    return;
  }
  ms_strbuild_append_text(out, "add `");
  ms_ty_show(out, program->names, &program->types, part);
  ms_strbuild_append_text(out, ": Data` to the type parameter");
}

/* ---- the properties ---- */

static bool property_in(MsCheckProgram *program, MsTy ty, MsProperty property);

static MsBuiltin property_builtin(MsProperty property) {
  static const MsBuiltin builtins[] = {MS_BUILTIN_Equal, MS_BUILTIN_Hashable, MS_BUILTIN_Clonable, MS_BUILTIN_Data};
  return builtins[property];
}

/* A bound that makes a variable Clonable: Data and Hashable hold no resource or function either. */
static bool implies_clonable(const MsTyTable *types, MsTy bound) {
  return ms_ty_is(types, bound, MS_BUILTIN_Clonable) || ms_ty_is(types, bound, MS_BUILTIN_Data) ||
         ms_ty_is(types, bound, MS_BUILTIN_Hashable);
}

/* Whether every field and case payload of `ty` has `property`. */
static bool parts_have(MsCheckProgram *program, MsTy ty, MsProperty property) {
  const MsDef *def = def_of(program, ty);
  for (size_t index = 0; def != NULL && index < def->fields.len; index++) {
    if (!property_in(program, part_type(program, ty, def, def->fields.ptr[index].ty), property)) {
      return false;
    }
  }
  for (size_t index = 0; def != NULL && index < def->cases.len; index++) {
    for (size_t at = 0; at < def->cases.ptr[index].fields.len; at++) {
      if (!property_in(program, part_type(program, ty, def, def->cases.ptr[index].fields.ptr[at].ty), property)) {
        return false;
      }
    }
  }
  return true;
}

static bool args_have(MsCheckProgram *program, MsTy ty, MsProperty property) {
  for (size_t index = 0; index < ms_ty_arg_count(&program->types, ty); index++) {
    if (!property_in(program, ms_ty_args(&program->types, ty)[index], property)) {
      return false;
    }
  }
  return true;
}

/* A native declares an infallible `clone` of its own, as an operation of its definition or as a method. */
static bool declares_clone(MsCheckProgram *program, MsTy ty) {
  const MsDef *def = def_of(program, ty);
  const MsName clone = name_of(program, "clone");
  for (size_t index = 0; def != NULL && index < def->operations.len; index++) {
    const MsOperation *operation = &def->operations.ptr[index];
    if (operation->name == clone && ms_ty_result(&program->types, operation->ty) == program->symbols.ptr[def->symbol].ty) {
      return true;
    }
  }
  MsMethodMatchList found = {0};
  bool any = false;
  ms_check_find_method(program, ty, clone, &found);
  for (size_t index = 0; index < found.len && !any; index++) {
    any = found.ptr[index].entry != NULL && ms_ty_result(&program->types, found.ptr[index].ty) == ty;
  }
  ms_method_match_list_free(&found);
  return any;
}

static bool clonable(MsCheckProgram *program, MsTy ty) {
  const MsTyTable *types = &program->types;
  switch (ms_ty_kind(types, ty)) {
  case MS_TY_VARIABLE: {
    const MsTyVariable *record = ms_ty_variable(&program->types, ty);
    for (size_t index = 0; index < record->bounds.len; index++) {
      if (implies_clonable(types, record->bounds.ptr[index])) {
        return true;
      }
    }
    return false;
  }
  case MS_TY_CONTRACT:
    return !ms_ty_is(types, ty, MS_BUILTIN_Closeable);
  case MS_TY_FUNCTION:
    return false;
  case MS_TY_PRIMITIVE:
    return true;
  default:
    break;
  }
  const MsDef *def = def_of(program, ty);
  if (def != NULL && has_marker(program, def, "clonable")) {
    return true;
  }
  if (ms_check_closeable(program, ty)) {
    return false;
  }
  if (ms_ty_kind(types, ty) == MS_TY_NATIVE) {
    return (ms_ty_is(types, ty, MS_BUILTIN_Decimal) || declares_clone(program, ty)) &&
           args_have(program, ty, MS_PROPERTY_CLONABLE);
  }
  return def != NULL ? parts_have(program, ty, MS_PROPERTY_CLONABLE) : true;
}

/* The own method `equals(other: Self) Bool` or `hash() Int` decides Equal or Hashable for the type. */
static bool decided_by_method(MsCheckProgram *program, MsTy ty, MsProperty property) {
  if (property == MS_PROPERTY_EQUAL) {
    return has_own_method(program, ty, "equals", 1, MS_BUILTIN_Bool, true);
  }
  return has_own_method(program, ty, "hash", 0, MS_BUILTIN_Int, false);
}

static bool compute(MsCheckProgram *program, MsTy ty, MsProperty property) {
  const MsTyTable *types = &program->types;
  if (property == MS_PROPERTY_CLONABLE) {
    return clonable(program, ty);
  }
  if (ms_ty_kind(types, ty) == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(&program->types, ty);
    for (size_t index = 0; index < record->bounds.len; index++) {
      const MsTy bound = record->bounds.ptr[index];
      if (ms_ty_is(types, bound, property_builtin(property)) ||
          (ms_ty_is(types, bound, MS_BUILTIN_Hashable) && property == MS_PROPERTY_EQUAL)) {
        return true;
      }
    }
    return false;
  }
  if (decided_by_method(program, ty, property)) {
    return property != MS_PROPERTY_HASHABLE ||
           (!holds_resource_anywhere(program, ty) && property_in(program, ty, MS_PROPERTY_EQUAL));
  }
  if (property == MS_PROPERTY_HASHABLE && decided_by_method(program, ty, MS_PROPERTY_EQUAL)) {
    return false; /* its own equality needs its own hash */
  }
  switch (ms_ty_kind(types, ty)) {
  case MS_TY_FUNCTION:
  case MS_TY_CONTRACT:
    return false;
  case MS_TY_PRIMITIVE:
    return !ms_builtin_is_float(ms_ty_builtin(types, ty)) || property != MS_PROPERTY_HASHABLE;
  default:
    break;
  }
  const MsBuiltin builtin = ms_ty_builtin(types, ty);
  if (builtin == MS_BUILTIN_Decimal || builtin == MS_BUILTIN_Bytes) {
    return true;
  }
  if (builtin == MS_BUILTIN_List || builtin == MS_BUILTIN_Map || builtin == MS_BUILTIN_Set) {
    return property != MS_PROPERTY_HASHABLE && args_have(program, ty, property);
  }
  if (builtin == MS_BUILTIN_BigInt || builtin == MS_BUILTIN_Regex || builtin == MS_BUILTIN_Timestamp) {
    return property == MS_PROPERTY_EQUAL && builtin != MS_BUILTIN_Regex;
  }
  if (ms_ty_kind(types, ty) == MS_TY_NATIVE) {
    return false;
  }
  return def_of(program, ty) != NULL && parts_have(program, ty, property);
}

static const MsPropertyKey *find_key(const MsPropertyKeyList *list, MsTy ty, MsProperty property) {
  for (size_t index = 0; index < list->len; index++) {
    if (list->ptr[index].ty == ty && list->ptr[index].property == (uint8_t)property) {
      return &list->ptr[index];
    }
  }
  return NULL;
}

static bool property_in(MsCheckProgram *program, MsTy ty, MsProperty property) {
  if (ms_ty_is_invalid(&program->types, ty) || ty == MS_TY_NONE) {
    return true;
  }
  if (property == MS_PROPERTY_DATA) {
    MsStrBuild path = ms_strbuild_new();
    MsDataReason reason;
    MsTy part;
    const bool held = !ms_check_data_blocker(program, ty, &path, &reason, &part);
    ms_strbuild_free(&path);
    return held;
  }
  if ((property == MS_PROPERTY_HASHABLE || property == MS_PROPERTY_CLONABLE) && holds_resource_anywhere(program, ty)) {
    return false;
  }
  MsPropertyMemo *memo = &program->properties;
  const MsPropertyKey *known = find_key(&memo->done, ty, property);
  if (known != NULL && known->methods == program->methods.len) {
    return known->result;
  }
  if (find_key(&memo->active, ty, property) != NULL) {
    return property != MS_PROPERTY_HASHABLE; /* equality copes with cycles; hashing needs an acyclic shape */
  }
  ms_property_key_list_push(&memo->active, (MsPropertyKey){.ty = ty, .property = (uint8_t)property});
  const bool result = compute(program, ty, property);
  ms_property_key_list_truncate(&memo->active, memo->active.len - 1);
  if (memo->active.len == 0) { /* an answer computed under an assumed ancestor must not outlive it */
    ms_property_key_list_push(&memo->done, (MsPropertyKey){.ty = ty, .property = (uint8_t)property, .result = result,
                                                           .methods = (uint32_t)program->methods.len});
  }
  return result;
}

bool ms_check_property(MsCheckProgram *program, MsTy ty, MsProperty property) {
  return property_in(program, ty, property);
}
