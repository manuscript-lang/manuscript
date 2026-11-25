/* compiler/check/methods.c: registers a module's methods and finds the methods of a receiver.
 *
 * `fn Type[T: Bound].name(...)` becomes one entry: the receiver form (the written arguments, with a fresh
 * variable per type parameter the form leaves open), the method's own type parameters, and the signature with
 * `Self` read as the receiver. A method of a type another module declares, of an interface, or of a built-in
 * type is reported and not registered; the standard modules may extend built-in scalars and native types. */
#include "compiler/check/methods.h"

#include <string.h>

#include "base/alloc.h"
#include "base/sort.h"
#include "compiler/check/bounds.h"
#include "compiler/check/resolve_internal.h"

MS_MAP_DEFINE(MsNameHeads, ms_name_heads, uint64_t, uint32_t, ms_hash_u64_key, ms_equal_u64_key)

/* The entries this call registers, which the program's index does not cover yet, chained by name and receiver type
 * (forms of other types are never related), so that finding the earlier forms costs the entries of that name on that
 * type, not all of them: `heads` maps the key to its latest pending entry, `next[entry - first]` to the one before it
 * (or NO_ENTRY). */
typedef struct Pending {
  MsNameHeads heads;
  uint32_t *next;
  size_t first, len, cap;
} Pending;

#define NO_ENTRY UINT32_MAX

typedef struct Context {
  Resolver resolver;
  MsCheckProgram *program;
  uint32_t module;
  MsTyList fresh;       /* the receiver form's variables, in step with the symbol's */
  MsTyList open;        /* the ones the receiver mentions */
  Pending pending;
} Context;

static uint64_t pending_key(const MsCheckProgram *program, MsName name, MsTy receiver) {
  return (uint64_t)name << 32 | ms_ty_row(&program->types, receiver)->id;
}

/* Notes entry `entry` (just pushed) under `key`. */
static void pending_add(Pending *pending, uint64_t key, size_t entry) {
  if (pending->len == pending->cap) {
    pending->cap = pending->cap == 0 ? 64 : pending->cap * 2;
    pending->next = ms_realloc(pending->next, pending->cap * sizeof *pending->next);
  }
  const uint32_t *head = ms_name_heads_get(&pending->heads, key);
  pending->next[entry - pending->first] = head != NULL ? *head : NO_ENTRY;
  pending->len++;
  ms_name_heads_put(&pending->heads, key, (uint32_t)entry);
}

static void report(const Context *context, MsPos pos, const char *prefix, MsName name, const char *suffix) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, prefix);
  ms_strbuild_append(&text, ms_names_span(context->program->names, name));
  ms_strbuild_append_text(&text, suffix);
  ms_check_report(context->program, context->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

void ms_methods_free(MsMethodList *methods) {
  for (size_t index = 0; index < methods->len; index++) {
    ms_ty_list_free(&methods->ptr[index].variables);
  }
  ms_method_list_free(methods);
}

/* ---- receivers ---- */

/* Whether `ty` is `variable` or mentions it. */
static bool mentions(const MsTyTable *types, MsTy ty, MsTy variable) {
  if (ty == variable) {
    return true;
  }
  if (!ms_ty_has_variable(types, ty)) {
    return false;
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (mentions(types, ms_ty_args(types, ty)[index], variable)) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (mentions(types, ms_ty_params(types, ty)[index].ty, variable)) {
      return true;
    }
  }
  return ms_ty_result(types, ty) != MS_TY_NONE && mentions(types, ms_ty_result(types, ty), variable);
}

/* Whether the module writes a type, enum or interface declaration named `name`. */
static bool declared_here(const MsCheckProgram *program, uint32_t module, const MsDecl *impl, MsName name) {
  (void)impl;
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    const bool named = (decl->kind == MS_D_TYPE && decl->u.type.name == name) ||
                       (decl->kind == MS_D_ENUM && decl->u.enumeration.name == name) ||
                       (decl->kind == MS_D_INTERFACE && decl->u.iface.name == name);
    if (named) {
      return true;
    }
  }
  return false;
}

/* Whether an earlier method block of this module already reported a receiver named `name` (true), else records it. */
static bool receiver_reported(const MsCheckProgram *program, uint32_t module, const MsDecl *impl, MsName name) {
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls && tree->decls[index] != impl; index++) {
    const MsDecl *earlier = tree->decls[index];
    if (earlier->kind == MS_D_IMPL && earlier->u.impl.contract == NULL && earlier->u.impl.receiver->name == name) {
      return true;
    }
  }
  return false;
}

/* The symbol that declares the type named by the receiver of `decl`, or 0 with the reason reported. The
 * standard modules may also name built-in types, which have no symbol: `*primitive` is then set. */
static MsSymbolId receiver_symbol(Context *context, const MsDecl *decl, bool *primitive) {
  const MsCheckProgram *program = context->program;
  const MsTypeRef *receiver = decl->u.impl.receiver;
  const bool standard = !ms_check_is_user_module(program, context->module);
  const MsSymbolId *own = ms_scope_get(&program->modules.ptr[context->module].scope, receiver->name);
  const MsSymbolId *imported = ms_scope_get(&program->modules.ptr[context->module].imports, receiver->name);
  MsSymbolId id = own != NULL ? *own : 0;
  *primitive = false;
  if (id == 0 && standard) {
    id = imported != NULL ? *imported : 0;
    if (id == 0 && ms_builtin_primitive(ms_names_span(program->names, receiver->name)) != MS_BUILTIN_NONE) {
      *primitive = true;
      return 1; /* a stand-in: the caller reads `primitive` */
    }
  }
  if (id == 0 && declared_here(program, context->module, decl, receiver->name)) {
    /* The module declares a type of that name, but it reuses a prelude name and is not entered: the methods of one
     * receiver form merge into a block, and the block is reported once. */
    if (!receiver_reported(program, context->module, decl, receiver->name)) {
      ms_check_report(context->program, context->module, decl->pos, MS_CHECK_TYPE,
                      ms_string_from_span(ms_span_of_text("implementation receiver must be nominal source data; declare methods on a type or enum you declare, such as 'fn Point.show() String { ... }', not on built-in or function types")));
    }
    return 0;
  }
  if (id == 0 || program->symbols.ptr[id].kind != MS_SYMBOL_TYPE) {
    report(context, decl->pos, "inherent methods belong in the module that declares ", receiver->name,
           "; to add operations to another module's type, write a free function or a wrapper type");
    return 0;
  }
  return id;
}

/* The names `[T, U]` of a symbol's type parameters, for the argument-count message. */
static void append_parameter_names(const Context *context, const MsSymbol *symbol, MsStrBuild *text) {
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  for (uint32_t index = 0; index < params.len; index++) {
    ms_strbuild_append_text(text, index == 0 ? "[" : ", ");
    ms_strbuild_append(text, ms_names_span(context->program->names, params.ptr[index]->name));
  }
  ms_strbuild_append_text(text, params.len > 0 ? "]" : "");
}

/* Whether `name` is written inside `ref`, as a type or a type argument, in any nested position. */
static bool writes_name(const MsTypeRef *ref, MsName name) {
  if (ref == NULL) {
    return false;
  }
  if (ref->name == name && ref->args.len == 0 && ref->params.len == 0) {
    return true;
  }
  for (uint32_t index = 0; index < ref->args.len; index++) {
    if (writes_name(ref->args.ptr[index], name)) {
      return true;
    }
  }
  for (uint32_t index = 0; index < ref->params.len; index++) {
    if (writes_name(ref->params.ptr[index]->ty, name)) {
      return true;
    }
  }
  return writes_name(ref->result, name);
}

/* Gives the receiver form a fresh variable per type parameter of `symbol`, bounded as the declaration bounds it
 * (and as the form writes), and enters their names. */
static void enter_form_variables(Context *context, const MsSymbol *symbol, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  for (uint32_t index = 0; index < params.len; index++) {
    const MsName id = ms_check_unique_id(program, "var");
    const MsTy variable = ms_ty_variable_new(&program->types, params.ptr[index]->name, id);
    ms_ty_list_push(&context->fresh, variable);
    /* The name is in scope only where the receiver writes it as a bare argument: `fn Box[Int].get() T` does not. */
    const MsTypeRef *written = index < decl->u.impl.receiver->args.len ? decl->u.impl.receiver->args.ptr[index] : NULL;
    const bool nested = written != NULL && written->args.len + written->params.len != 0 && writes_name(written, params.ptr[index]->name);
    if (written != NULL && ((written->name == params.ptr[index]->name && written->args.len == 0) || nested)) {
      ms_name_list_push(&context->resolver.names, params.ptr[index]->name);
      ms_ty_list_push(&context->resolver.types, variable);
    }
  }
  /* A bound names the type's other parameters: where the form writes a type there, the bound names that type. */
  MsTyList shown = {0};
  const bool report = context->resolver.report;
  context->resolver.report = false;
  for (uint32_t index = 0; index < params.len; index++) {
    const MsTypeRef *written = index < decl->u.impl.receiver->args.len ? decl->u.impl.receiver->args.ptr[index] : NULL;
    const bool bare = written != NULL && written->name == params.ptr[index]->name && written->args.len == 0;
    const bool named = written != NULL && !bare && !writes_name(written, params.ptr[index]->name);
    ms_ty_list_push(&shown, named ? resolver_type(&context->resolver, written) : context->fresh.ptr[index]);
    if (shown.ptr[index] == MS_TY_NONE) {
      shown.ptr[index] = context->fresh.ptr[index];
    }
  }
  context->resolver.report = report;
  for (uint32_t index = 0; index < params.len; index++) {
    MsTyVariable *record = ms_ty_variable(&program->types, context->fresh.ptr[index]);
    const MsTyVariable *declared =
        ms_ty_variable(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    for (size_t at = 0; at < declared->bounds.len; at++) {
      ms_ty_list_push(&record->bounds,
                      ms_ty_subst(&program->types, declared->bounds.ptr[at],
                                  program->symbol_vars.ptr + symbol->var_at, shown.ptr, params.len));
    }
    record->lends = declared->lends;
    for (uint32_t written = 0; written < decl->u.impl.bounds.len; written++) {
      const MsTypeParam *param = decl->u.impl.bounds.ptr[written];
      for (uint32_t bound = 0; param->name == params.ptr[index]->name && bound < param->bounds.len; bound++) {
        context->resolver.allow_type_set = true;
        ms_check_push_bound(record, resolver_type(&context->resolver, param->bounds.ptr[bound]), param->bounds.ptr[bound]);
        context->resolver.allow_type_set = false;
      }
    }
  }
  ms_ty_list_free(&shown);
}

/* ---- one method ---- */

/* How two receiver forms of one type compare: they could never match the same application, they could, or they
 * are the same form written twice (bare type parameters at the same positions, the same arguments elsewhere, the
 * same written bounds). Only forms under the same bounds can overlap. */
typedef enum FormRelation { FORM_DISJOINT, FORM_OVERLAP, FORM_SAME } FormRelation;

static bool is_variable(const MsTyTable *types, MsTy ty) {
  return ms_ty_kind(types, ty) == MS_TY_VARIABLE;
}

static bool same_bounds(MsCheckProgram *program, MsTy mine, MsTy theirs, const MsTy *from, const MsTy *to,
                        size_t count) {
  const MsTyVariable *a = ms_ty_variable(&program->types, mine);
  const MsTyVariable *b = ms_ty_variable(&program->types, theirs);
  if (a->bounds.len != b->bounds.len || a->lends != b->lends) {
    return false;
  }
  for (size_t index = 0; index < a->bounds.len; index++) {
    const MsTy bound = ms_ty_subst(&program->types, a->bounds.ptr[index], from, to, count);
    bool found = false;
    for (size_t at = 0; at < b->bounds.len && !found; at++) {
      found = b->bounds.ptr[at] == bound;
    }
    if (!found) {
      return false;
    }
  }
  return true;
}

static FormRelation relate_forms(MsCheckProgram *program, MsTy mine, const MsMethodEntry *other) {
  const MsTyTable *types = &program->types;
  const MsTy theirs = other->receiver;
  if (ms_ty_row(types, mine)->id != ms_ty_row(types, theirs)->id || ms_ty_arg_count(types, mine) != ms_ty_arg_count(types, theirs)) {
    return FORM_DISJOINT;
  }
  bool same = true;
  MsTyList from = {0};
  MsTyList to = {0};
  for (size_t index = 0; index < ms_ty_arg_count(types, mine); index++) {
    const MsTy a = ms_ty_args(types, mine)[index];
    const MsTy b = ms_ty_args(types, theirs)[index];
    if (is_variable(types, a) && is_variable(types, b)) {
      ms_ty_list_push(&from, a);
      ms_ty_list_push(&to, b);
    } else if (a != b) {
      same = false;
      if (!ms_ty_has_variable(types, a) && !ms_ty_has_variable(types, b)) {
        ms_ty_list_free(&from);
        ms_ty_list_free(&to);
        return FORM_DISJOINT;
      }
    }
  }
  bool bounds = true;
  for (size_t index = 0; bounds && index < from.len; index++) {
    bounds = same_bounds(program, from.ptr[index], to.ptr[index], from.ptr, to.ptr, from.len);
  }
  ms_ty_list_free(&from);
  ms_ty_list_free(&to);
  if (!bounds) {
    return FORM_DISJOINT;
  }
  return same ? FORM_SAME : FORM_OVERLAP;
}

static size_t lower_bound(const MsMethodKeyList *list, uint64_t key);

/* The strongest relation of `receiver` to one earlier entry of this module that declares the name. */
static FormRelation relate_entry(MsCheckProgram *program, MsTy receiver, const MsMethodEntry *entry, FormRelation best) {
  const FormRelation relation = entry->receiver == receiver ? FORM_SAME : relate_forms(program, receiver, entry);
  return relation > best ? relation : best;
}

/* The relation of the strongest earlier form of this module that declares `name`: the entries the index covers, then
 * the ones this call registered before. */
static FormRelation earlier_form(Context *context, MsTy receiver, MsName name) {
  MsCheckProgram *program = context->program;
  FormRelation result = FORM_DISJOINT;
  const MsMethodKeyList *named = &program->method_index.by_name;
  for (size_t slot = lower_bound(named, name); slot < named->len && named->ptr[slot].key == name; slot++) {
    const MsMethodEntry *entry = &program->methods.ptr[named->ptr[slot].entry];
    if (entry->module == context->module && ms_ty_row(&program->types, entry->receiver)->id == ms_ty_row(&program->types, receiver)->id) {
      result = relate_entry(program, receiver, entry, result);
    }
  }
  const uint32_t *head = ms_name_heads_get(&context->pending.heads, pending_key(program, name, receiver));
  for (uint32_t entry = head != NULL ? *head : NO_ENTRY; entry != NO_ENTRY;
       entry = context->pending.next[entry - context->pending.first]) {
    result = relate_entry(program, receiver, &program->methods.ptr[entry], result);
  }
  return result;
}

/* The method's own type parameters, entered in scope and bounded; a name the receiver form already uses is
 * reported. */
static void enter_own_variables(Context *context, const MsMethod *method, MsTyList *own) {
  MsCheckProgram *program = context->program;
  for (uint32_t index = 0; index < method->func.type_params.len; index++) {
    const MsTypeParam *param = method->func.type_params.ptr[index];
    for (size_t at = 0; at < context->resolver.names.len; at++) {
      if (context->resolver.names.ptr[at] == param->name) {
        report(context, param->pos, "type parameter ", param->name,
               " shadows a type parameter of the receiver type; choose a different name");
        break;
      }
    }
    if (ms_check_is_user_module(program, context->module) && ms_check_intrinsic_type_param(program, param->name)) {
      ms_check_report_type_param(program, context->module, param);
    }
    const MsTy variable = ms_ty_variable_new(&program->types, param->name, ms_check_unique_id(program, "var"));
    ms_ty_list_push(own, variable);
    ms_name_list_push(&context->resolver.names, param->name);
    ms_ty_list_push(&context->resolver.types, variable);
  }
  for (uint32_t index = 0; index < method->func.type_params.len; index++) {
    const MsTypeParam *param = method->func.type_params.ptr[index];
    MsTyVariable *record = ms_ty_variable(&program->types, own->ptr[index]);
    for (uint32_t bound = 0; bound < param->bounds.len; bound++) {
      context->resolver.allow_type_set = true;
      ms_check_push_bound(record, resolver_type(&context->resolver, param->bounds.ptr[bound]), param->bounds.ptr[bound]);
      context->resolver.allow_type_set = false;
    }
    if (param->def != NULL) {
      record->default_ty = resolver_type(&context->resolver, param->def);
    }
  }
}

static void add_methods(Context *context, const MsDecl *decl, MsTy receiver) {
  MsCheckProgram *program = context->program;
  Resolver *resolver = &context->resolver;
  const size_t form_mark = resolver->names.len;
  resolver->self = receiver;
  for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
    const MsMethod *method = decl->u.impl.methods.ptr[index];
    MsTyList own = {0};
    enter_own_variables(context, method, &own);
    const MsTy signature = resolver_function(resolver, method->func.params, method->func.result);
    const FormRelation relation = earlier_form(context, receiver, method->func.name);
    if (relation == FORM_SAME) {
      report(context, method->pos, "duplicate operation ", method->func.name, "; rename or remove one of them");
    } else if (relation == FORM_OVERLAP) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "duplicate or overlapping implementation of ");
      ms_strbuild_append(&text, ms_names_span(program->names, method->func.name));
      ms_strbuild_append_text(&text, " on ");
      ms_strbuild_append(&text, ms_names_span(program->names, ms_ty_row(&program->types, receiver)->name));
      ms_strbuild_append_text(&text, ": another receiver form of the same type could match the same application");
      ms_check_report(program, context->module, method->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
    MsMethodEntry entry = {.name = method->func.name, .receiver = receiver, .ty = signature,
                           .module = context->module, .source = method};
    ms_ty_list_reserve(&entry.variables, context->open.len + own.len);
    for (size_t at = 0; at < context->open.len; at++) {
      ms_ty_list_push(&entry.variables, context->open.ptr[at]);
    }
    entry.shared = (uint32_t)context->open.len;
    for (size_t at = 0; at < own.len; at++) {
      ms_ty_list_push(&entry.variables, own.ptr[at]);
    }
    ms_method_list_push(&program->methods, entry);
    pending_add(&context->pending, pending_key(program, method->func.name, receiver), program->methods.len - 1);
    ms_ty_list_free(&own);
    ms_name_list_truncate(&resolver->names, form_mark);
    ms_ty_list_truncate(&resolver->types, form_mark);
  }
}

/* The variable a type-set method's receiver is: `fn Ordered.min(...)` over `type Ordered = Int | Float | ...` reads
 * as `fn[Self: Ordered] Self.min(...)`, so one body serves every member and lowering binds `Self` per call. It is
 * bounded by the set and by each standard interface all the members implement. */
static MsTy set_receiver(Context *context, MsTy set, const MsTyList *members) {
  MsCheckProgram *program = context->program;
  const MsTy self = ms_ty_variable_new(&program->types, ms_names_intern(program->names, ms_span_of_text("Self")),
                                       ms_check_unique_id(program, "var"));
  ms_ty_list_push(&context->fresh, self);
  ms_ty_list_push(&context->open, self);
  MsTyVariable *record = ms_ty_variable(&program->types, self);
  ms_ty_list_push(&record->bounds, set);
  static const char *const contracts[] = {"Comparable", "Equal", "Hashable", "Clonable", "Data"};
  for (size_t index = 0; index < MS_COUNT_OF(contracts); index++) {
    const MsSymbolId symbol =
        resolver_prelude_symbol(program, ms_names_intern(program->names, ms_span_of_text(contracts[index])));
    bool all = symbol != 0 && program->symbols.ptr[symbol].ty != MS_TY_NONE;
    for (size_t at = 0; all && at < members->len; at++) {
      all = ms_check_implements(program, members->ptr[at], program->symbols.ptr[symbol].ty);
    }
    if (all) {
      ms_ty_list_push(&record->bounds, program->symbols.ptr[symbol].ty);
    }
  }
  return self;
}

/* `fn Ordered.min(...)` over a type set: the method exists on every member. */
static bool add_set_block(Context *context, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  const MsSymbolId *own = ms_scope_get(&program->modules.ptr[context->module].scope, decl->u.impl.receiver->name);
  if (own == NULL || program->symbols.ptr[*own].kind != MS_SYMBOL_ALIAS || decl->u.impl.receiver->args.len != 0) {
    return false;
  }
  const MsDecl *alias = program->symbols.ptr[*own].decl;
  if (alias->u.alias.type_params.len != 0 || alias->u.alias.targets.len < 2) {
    return false;
  }
  ms_name_list_truncate(&context->resolver.names, 0);
  ms_ty_list_truncate(&context->resolver.types, 0);
  ms_ty_list_truncate(&context->fresh, 0);
  ms_ty_list_truncate(&context->open, 0);
  MsTyList members = {0};
  for (uint32_t index = 0; index < alias->u.alias.targets.len; index++) {
    context->resolver.allow_type_set = true;
    const MsTy member = resolver_type(&context->resolver, alias->u.alias.targets.ptr[index]);
    context->resolver.allow_type_set = false;
    if (member != MS_TY_NONE) {
      ms_ty_list_push(&members, member);
    }
  }
  context->resolver.allow_type_set = true;
  const MsTy set = resolver_type(&context->resolver, decl->u.impl.receiver);
  context->resolver.allow_type_set = false;
  if (set != MS_TY_NONE && ms_ty_is(&program->types, set, MS_BUILTIN_TypeSet) && members.len != 0) {
    add_methods(context, decl, set_receiver(context, set, &members));
  }
  ms_ty_list_free(&members);
  return true;
}

static void add_block(Context *context, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  Resolver *resolver = &context->resolver;
  if (add_set_block(context, decl)) {
    return;
  }
  bool primitive = false;
  const MsSymbolId id = receiver_symbol(context, decl, &primitive);
  if (id == 0) {
    return;
  }
  ms_name_list_truncate(&resolver->names, 0);
  ms_ty_list_truncate(&resolver->types, 0);
  ms_ty_list_truncate(&context->fresh, 0);
  ms_ty_list_truncate(&context->open, 0);
  MsTy receiver = MS_TY_NONE;
  size_t receiver_start = 0;
  size_t receiver_end = 0;
  if (primitive) {
    receiver = resolver_type(resolver, decl->u.impl.receiver);
  } else {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    MsStrBuild text = ms_strbuild_new();
    if (symbol->def != 0 && ms_defs_get(&program->defs, symbol->def)->kind == MS_TY_CONTRACT) {
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      ms_strbuild_append_text(&text, " is an interface; a method belongs to a type, and a type whose methods match the interface satisfies it");
    } else if (decl->u.impl.receiver->args.len != symbol->var_count) {
      ms_strbuild_append_text(&text, "a method of ");
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      ms_strbuild_append_text(&text, " names one receiver argument per type parameter, as in 'fn ");
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      append_parameter_names(context, symbol, &text);
      ms_strbuild_append_text(&text, ".name()'");
    }
    if (ms_strbuild_length(&text) > 0) {
      ms_check_report(program, context->module, decl->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      return;
    }
    ms_strbuild_free(&text);
    enter_form_variables(context, symbol, decl);
    receiver_start = program->diagnostics.len;
    receiver = resolver_type(resolver, decl->u.impl.receiver);
    receiver_end = program->diagnostics.len;
    for (size_t at = 0; at < context->fresh.len; at++) {
      if (mentions(&program->types, receiver, context->fresh.ptr[at])) {
        ms_ty_list_push(&context->open, context->fresh.ptr[at]);
      }
    }
  }
  if (receiver == MS_TY_NONE) {
    return;
  }
  add_methods(context, decl, receiver);
  /* The oracle reports the receiver's own diagnostics after those of the signatures. */
  const size_t end = program->diagnostics.len;
  if (receiver_end > receiver_start && end > receiver_end) {
    MsCheckDiagList *list = &program->diagnostics;
    const size_t count = receiver_end - receiver_start;
    MsCheckDiag *held = MS_ARENA_NEW_ARRAY(&program->arena, MsCheckDiag, count);
    memcpy(held, list->ptr + receiver_start, count * sizeof *held);
    memmove(list->ptr + receiver_start, list->ptr + receiver_end, (end - receiver_end) * sizeof *held);
    memcpy(list->ptr + (end - count), held, count * sizeof *held);
  }
}

static int64_t compare_keys(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsMethodKey *a = (const MsMethodKey *)(const void *)left;
  const MsMethodKey *b = (const MsMethodKey *)(const void *)right;
  if (a->key != b->key) {
    return a->key < b->key ? -1 : 1;
  }
  return a->entry < b->entry ? -1 : a->entry > b->entry;
}

/* Adds the entries from `from` on to the sorted `list`: sorts the new keys and merges them in. */
static void extend_index(MsMethodKeyList *list, const MsMethodList *methods, size_t from, bool by_name) {
  MsMethodKeyList added = {0};
  for (size_t index = from; index < methods->len; index++) {
    const MsMethodEntry *entry = &methods->ptr[index];
    const uint64_t key = by_name ? entry->name : (uint64_t)entry->module << 32 | entry->source->id;
    ms_method_key_list_push(&added, (MsMethodKey){.key = key, .entry = (uint32_t)index});
  }
  if (added.len > 1) {
    ms_sort((uint8_t *)added.ptr, added.len, sizeof *added.ptr, compare_keys, NULL);
  }
  MsMethodKeyList merged = {0};
  ms_method_key_list_reserve(&merged, list->len + added.len);
  size_t left = 0;
  size_t right = 0;
  while (left < list->len || right < added.len) {
    const bool take_left = right == added.len || (left < list->len && compare_keys(NULL, (const uint8_t *)&list->ptr[left], (const uint8_t *)&added.ptr[right]) <= 0);
    ms_method_key_list_push(&merged, take_left ? list->ptr[left++] : added.ptr[right++]);
  }
  ms_method_key_list_free(list);
  ms_method_key_list_free(&added);
  *list = merged;
}

static void index_methods(MsCheckProgram *program) {
  MsMethodIndex *index = &program->method_index;
  extend_index(&index->by_name, &program->methods, index->indexed, true);
  extend_index(&index->by_decl, &program->methods, index->indexed, false);
  index->indexed = program->methods.len;
}

/* The first key at or after `key`. */
static size_t lower_bound(const MsMethodKeyList *list, uint64_t key) {
  size_t low = 0;
  size_t high = list->len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (list->ptr[mid].key < key) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

const MsMethodEntry *ms_check_method_at(const MsCheckProgram *program, uint32_t module, uint32_t node) {
  const MsMethodKeyList *list = &program->method_index.by_decl;
  const uint64_t key = (uint64_t)module << 32 | node;
  const size_t at = lower_bound(list, key);
  return at < list->len && list->ptr[at].key == key ? &program->methods.ptr[list->ptr[at].entry] : NULL;
}

void ms_check_methods(MsCheckProgram *program, uint32_t module) {
  Context context = {.program = program, .module = module, .pending = {.first = program->methods.len}};
  resolver_init(&context.resolver, program, module);
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (ms_decl_is_inherent_impl(tree->decls[index])) {
      add_block(&context, tree->decls[index]);
    }
  }
  ms_ty_list_free(&context.fresh);
  ms_ty_list_free(&context.open);
  resolver_free(&context.resolver);
  ms_name_heads_free(&context.pending.heads);
  ms_free(context.pending.next);
  index_methods(program);
}

/* ---- lookup ---- */

bool ms_check_unify(const MsTyTable *types, MsTy pattern, MsTy actual, const MsTy *vars, size_t count,
                    MsTy *bound) {
  for (size_t index = 0; index < count; index++) {
    if (vars[index] != pattern) {
      continue;
    }
    if (bound[index] != MS_TY_NONE) {
      if (bound[index] == actual || ms_ty_same_view(types, bound[index], actual)) {
        return true;
      }
      /* `T?` is `T` or null, and `T??` is `T?`: the optional `Int?` unifies with `T?` as `T = Int` and as `T = Int?`,
       * so a variable bound one way takes the other. */
      const bool bound_wraps = ms_ty_is(types, bound[index], MS_BUILTIN_Optional) && ms_ty_arg_count(types, bound[index]) == 1;
      if (bound_wraps && ms_ty_args(types, bound[index])[0] == actual) {
        return true;
      }
      if (ms_ty_is(types, actual, MS_BUILTIN_Optional) && ms_ty_arg_count(types, actual) == 1 &&
          ms_ty_args(types, actual)[0] == bound[index]) {
        bound[index] = actual;
        return true;
      }
      return false;
    }
    /* A variable written bare is bound to the value, not the borrow: `List[T]` met by `List[&String]` is a list of
     * `String`, so a method that clones its items produces owned ones. */
    bound[index] = ms_ty_is_borrow(types, actual) ? ms_ty_args(types, actual)[0] : actual;
    return true;
  }
  if (!ms_ty_has_variable(types, pattern)) {
    return pattern == actual || ms_ty_same_view(types, pattern, actual);
  }
  while (ms_ty_is_borrow(types, actual)) {
    actual = ms_ty_args(types, actual)[0]; /* a borrow fills a pattern written for the value */
  }
  /* A pattern that is its own actual (a recursive call) still binds its variables, each to itself. */
  const MsTyRow *want = ms_ty_row(types, pattern);
  const MsTyRow *have = ms_ty_row(types, actual);
  if (want->id != have->id || want->kind != have->kind || want->arg_count != have->arg_count ||
      want->param_count != have->param_count) {
    return false;
  }
  for (uint32_t index = 0; index < want->arg_count; index++) {
    if (!ms_check_unify(types, ms_ty_args(types, pattern)[index], ms_ty_args(types, actual)[index], vars, count,
                        bound)) {
      return false;
    }
  }
  for (uint32_t index = 0; index < want->param_count; index++) {
    const MsTyParam *left = &ms_ty_params(types, pattern)[index];
    const MsTyParam *right = &ms_ty_params(types, actual)[index];
    if ((left->flags & ~MS_PARAM_LIFTED) != (right->flags & ~MS_PARAM_LIFTED) ||
        !ms_check_unify(types, left->ty, right->ty, vars, count, bound)) {
      return false;
    }
  }
  return want->kind != MS_TY_FUNCTION ||
         (want->result != MS_TY_NONE && have->result != MS_TY_NONE &&
          ms_check_unify(types, want->result, have->result, vars, count, bound));
}

/* Whether each of `variables` holds an argument that meets the variable's bounds. */
bool ms_check_bounds_satisfied(MsCheckProgram *program, const MsTy *variables, size_t count, const MsTy *bound) {
  for (size_t index = 0; index < count; index++) {
    if (bound[index] == MS_TY_NONE) {
      return false;
    }
    const MsTyVariable *record = ms_ty_variable(&program->types, variables[index]);
    for (size_t at = 0; at < record->bounds.len; at++) {
      const MsTy wanted = ms_ty_subst(&program->types, record->bounds.ptr[at], variables, bound, count);
      const bool lends = at < 32 && (record->lends & (UINT32_C(1) << at)) != 0;
      if (!ms_check_implements(program, bound[index], wanted) || (lends && !ms_check_lends(program, bound[index], wanted))) {
        return false;
      }
    }
  }
  return true;
}

static void find_in_contract(MsCheckProgram *program, MsTy contract, MsName name, MsTy implementor,
                             MsMethodMatchList *out) {
  const MsOperation *operation = ms_check_find_operation(program, contract, name);
  if (operation == NULL) {
    return;
  }
  for (size_t index = 0; index < out->len; index++) {
    if (out->ptr[index].operation == operation && out->ptr[index].contract == contract) {
      return; /* one bound inherited twice does not make the operation ambiguous */
    }
  }
  ms_method_match_list_push(out, (MsMethodMatch){
      .ty = ms_check_operation_type(program, contract, operation, implementor), .contract = contract,
      .operation = operation});
}

static bool has_lends(MsCheckProgram *program, const MsMethodEntry *entry) {
  for (uint32_t at = 0; at < entry->shared; at++) {
    if (ms_ty_variable(&program->types, entry->variables.ptr[at])->lends != 0) {
      return true;
    }
  }
  return false;
}

/* A lending source fits both the form written for lending iterators and the one for owning ones; the first is the
 * more specific, so it alone answers (`Seq.filter` borrows from a borrowing source and keeps what an owning one yields). */
static void prefer_lending(MsCheckProgram *program, MsMethodMatchList *out, size_t first) {
  bool lending = false;
  for (size_t at = first; at < out->len; at++) {
    lending |= has_lends(program, out->ptr[at].entry);
  }
  if (!lending) {
    return;
  }
  size_t kept = first;
  for (size_t at = first; at < out->len; at++) {
    if (has_lends(program, out->ptr[at].entry)) {
      out->ptr[kept++] = out->ptr[at];
    }
  }
  out->len = kept;
}

void ms_check_find_method(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  if (kind == MS_TY_CONTRACT) {
    find_in_contract(program, receiver, name, receiver, out);
    ms_check_find_native(program, receiver, name, out);
    return;
  }
  if (kind == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(&program->types, receiver);
    for (size_t index = 0; index < record->bounds.len; index++) {
      if (ms_ty_kind(&program->types, record->bounds.ptr[index]) == MS_TY_CONTRACT) {
        find_in_contract(program, record->bounds.ptr[index], name, receiver, out);
      }
    }
    ms_check_find_native(program, receiver, name, out);
    return;
  }
  const MsMethodKeyList *named = &program->method_index.by_name;
  const size_t first = out->len;
  for (size_t slot = lower_bound(named, name); slot < named->len && named->ptr[slot].key == name; slot++) {
    const MsMethodEntry *entry = &program->methods.ptr[named->ptr[slot].entry];
    MsTyList bound = {0};
    for (uint32_t at = 0; at < entry->shared; at++) {
      ms_ty_list_push(&bound, MS_TY_NONE);
    }
    const bool fits = ms_check_unify(&program->types, entry->receiver, receiver, entry->variables.ptr, entry->shared,
                                     bound.ptr) &&
                      ms_check_bounds_satisfied(program, entry->variables.ptr, entry->shared, bound.ptr);
    if (fits) {
      ms_method_match_list_push(out, (MsMethodMatch){
          .ty = ms_ty_subst(&program->types, entry->ty, entry->variables.ptr, bound.ptr, entry->shared),
          .entry = entry});
    }
    ms_ty_list_free(&bound);
  }
  prefer_lending(program, out, first);
  ms_check_find_native(program, receiver, name, out);
}
