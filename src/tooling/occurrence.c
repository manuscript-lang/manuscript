/* Owns occurrence.h. One pass per kind of occurrence, in the order of the oracle's builder: declarations, parameter
 * and binding sites, methods, written types, type parameters, then uses. Entries are sorted and de-duplicated at the
 * end, so the first one added for a (file, offset, key) wins. */
#include "tooling/occurrence.h"

#include "base/message.h"
#include "base/sort.h"
#include "compiler/check/methods.h"
#include "compiler/syntax/walk.h"
#include "tooling/facts.h"

typedef struct Builder {
  MsArena *arena;
  MsCheckProgram *program;
  MsOccurrences out;
  /* Per user module, indexed by node id. */
  MsSymbolId **symbol_at;               /* the symbol a declaration node declares */
  const MsMethodEntry ***method_at;     /* the method a method node declares */
  MsSpan **param_key;                   /* the key of the parameter or field a node declares */
  MsTy **written;                       /* the checked type of a written type node */
  bool **assigned;                      /* an expression that is the target of an assignment */
  uint32_t module;                      /* the module being walked */
  struct TypeSites *sink;               /* where the written-type collectors append */
  uint32_t **folded_into;               /* per declaration index: the first declaration whose receiver reads the same, or itself */
} Builder;

/* One written type: its node, the position of its name and the name; a function type has none. */
typedef struct TypeSite {
  uint32_t id, offset;
  MsName name;
  bool named;
} TypeSite;

MS_AVEC(TypeSites, type_sites, TypeSite)

static MsSpan name_text(const Builder *b, MsName name) {
  return ms_names_span(b->program->names, name);
}

static MsSpan module_file(const Builder *b, uint32_t module) {
  return name_text(b, b->program->modules.ptr[module].file);
}

static bool identifier_byte(uint8_t byte) {
  return byte == '_' || (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte >= 0x80;
}

/* Lowered suffixes and omitted arguments have checked facts but no name token. */
static bool written_name(MsSpan source, uint32_t offset, MsSpan name) {
  const size_t end = (size_t)offset + name.len;
  if (name.len == 0 || end > source.len || !ms_span_equal(ms_span_of(source.ptr + offset, name.len), name)) {
    return false;
  }
  return end == source.len || !identifier_byte(source.ptr[end]);
}

/* A declaration's name on the line after `offset` (a newline exactly at `offset` is skipped): the position of the
 * header's declared name, whatever precedes it. Falls back to `offset`. */
static uint32_t header(MsSpan source, uint32_t offset, MsSpan name) {
  size_t start = offset;
  if (start < source.len && source.ptr[start] == '\r' && start + 1 < source.len && source.ptr[start + 1] == '\n') {
    start += 2;
  } else if (start < source.len && source.ptr[start] == '\n') {
    start += 1;
  }
  size_t at = start;
  while (at < source.len && source.ptr[at] != '\n') {
    const uint8_t byte = source.ptr[at];
    if (byte == '"' || byte == '\'') {
      at++;
      while (at < source.len && source.ptr[at] != byte && source.ptr[at] != '\n') {
        at += source.ptr[at] == '\\' ? 2 : 1;
      }
      at++;
    } else if (byte == '/' && at + 1 < source.len && source.ptr[at + 1] == '/') {
      break;
    } else if (identifier_byte(byte) && !(byte >= '0' && byte <= '9')) {
      const size_t from = at;
      while (at < source.len && identifier_byte(source.ptr[at])) {
        at++;
      }
      if (ms_span_equal(ms_span_of(source.ptr + from, at - from), name)) {
        return (uint32_t)from;
      }
    } else {
      at++;
    }
  }
  return offset;
}

/* A written type as text: `Box[fn(Int) Int]`. Two methods share a receiver form when it reads the same. */
static void type_form(const Builder *b, MsStrBuild *out, const MsTypeRef *type) {
  if (type->kind == MS_TYPE_NAMED) {
    ms_strbuild_append(out, ms_names_span(b->program->names, type->name));
    for (uint32_t index = 0; index < type->args.len; index++) {
      ms_strbuild_append_text(out, index == 0 ? "[" : ",");
      type_form(b, out, type->args.ptr[index]);
    }
    ms_strbuild_append_text(out, type->args.len == 0 ? "" : "]");
    return;
  }
  ms_strbuild_append_text(out, "fn(");
  for (uint32_t index = 0; index < type->params.len; index++) {
    ms_strbuild_append_text(out, index == 0 ? "" : ",");
    ms_strbuild_append_text(out, type->params.ptr[index]->is_mutable ? "var " : "");
    if (type->params.ptr[index]->ty != NULL) {
      type_form(b, out, type->params.ptr[index]->ty);
    }
  }
  ms_strbuild_append_text(out, ")");
  if (type->result != NULL) {
    type_form(b, out, type->result);
  }
}

/* The methods of one receiver form are folded into the first: only that one writes the receiver as a type. */
static void fold_receivers(Builder *b, uint32_t module) {
  const MsModule *tree = b->program->modules.ptr[module].tree;
  b->folded_into[module] = MS_ARENA_NEW_ARRAY(b->arena, uint32_t, tree->ndecls + 1);
  MsSpan *forms = MS_ARENA_NEW_ARRAY(b->arena, MsSpan, tree->ndecls + 1);
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    b->folded_into[module][at] = at;
    if (tree->decls[at]->kind != MS_D_IMPL) {
      continue;
    }
    MsStrBuild text = ms_strbuild_new();
    type_form(b, &text, tree->decls[at]->u.impl.receiver);
    forms[at] = ms_arena_copy(b->arena, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
    for (uint32_t earlier = 0; earlier < at; earlier++) {
      if (tree->decls[earlier]->kind == MS_D_IMPL && b->folded_into[module][earlier] == earlier && ms_span_equal(forms[earlier], forms[at])) {
        b->folded_into[module][at] = earlier;
        break;
      }
    }
  }
}

/* ---- keys ---- */

static MsSpan symbol_key(const Builder *b, MsSymbolId id) {
  if (id == 0) {
    return (MsSpan){0};
  }
  const MsSymbol *symbol = &b->program->symbols.ptr[id];
  if (symbol->decl == NULL) {
    return ms_message_format(b->arena, "native:%S", name_text(b, symbol->id));
  }
  return ms_message_format(b->arena, "symbol:%S:%u", module_file(b, symbol->module), symbol->decl->pos.offset);
}

/* The symbol a nominal type was declared by, or 0. */
static MsSymbolId type_symbol(const Builder *b, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&b->program->types, ty);
  if (ty == MS_TY_NONE || row->def == 0 || row->kind == MS_TY_VARIABLE) {
    return 0;
  }
  return ms_defs_get(&b->program->defs, row->def)->symbol;
}

static MsSymbolId symbol_of_ref(const Builder *b, const MsRef *ref) {
  if (ref->decl.module >= b->program->user_modules || ref->decl.node == 0) {
    const MsModuleInfo *info = ref->decl.module < b->program->modules.len ? &b->program->modules.ptr[ref->decl.module] : NULL;
    if (info == NULL || ref->decl.node == 0 || ref->decl.node >= info->tree->node_count) {
      return 0;
    }
    for (size_t index = 1; index < b->program->symbols.len; index++) {
      const MsSymbol *symbol = &b->program->symbols.ptr[index];
      if (symbol->module == ref->decl.module && symbol->decl != NULL && symbol->decl->id == ref->decl.node) {
        return (MsSymbolId)index;
      }
    }
    return 0;
  }
  return b->symbol_at[ref->decl.module][ref->decl.node];
}

/* ---- adding ---- */

static void add(Builder *b, MsSpan key, MsSpan name, uint32_t module, uint32_t offset, bool declaration, bool write, MsTy ty,
                MsSymbolId symbol, bool method) {
  if (key.len == 0 || !written_name(b->program->modules.ptr[module].source, offset, name)) {
    return;
  }
  ms_occurrences_push(b->arena, &b->out,
                      (MsOccurrence){.key = key, .name = name, .module = module, .offset = offset,
                                     .end = offset + (uint32_t)name.len, .declaration = declaration, .write = write,
                                     .ty = ty, .symbol = symbol, .method = method});
}

static MsSpan source_of(const Builder *b, uint32_t module) {
  return b->program->modules.ptr[module].source;
}

/* ---- methods ---- */

typedef struct Operation {
  MsName name;
  MsTy contract;
  const MsOperation *op;
  MsSpan key;
} Operation;

static const MsMethodEntry *method_entry(const Builder *b, uint32_t module, MsNode node) {
  if (module >= b->program->user_modules) {
    for (size_t index = 0; index < b->program->methods.len; index++) {
      const MsMethodEntry *entry = &b->program->methods.ptr[index];
      if (entry->module == module && entry->source->id == node) {
        return entry;
      }
    }
    return NULL;
  }
  return node < b->program->modules.ptr[module].tree->node_count ? b->method_at[module][node] : NULL;
}

/* The identity of an interface operation: its interface's declaration and its name. */
static MsSpan operation_key(const Builder *b, MsSymbolId interface, MsName name) {
  const MsSymbol *symbol = &b->program->symbols.ptr[interface];
  if (symbol->decl == NULL) {
    return (MsSpan){0};
  }
  return ms_message_format(b->arena, "operation:%S:%u:%S", module_file(b, symbol->module), symbol->decl->pos.offset, name_text(b, name));
}

/* A method's identity. A type satisfies an interface by having its operations with the exact signature, so such a
 * method shares the operation's identity: renaming one renames the interface and every type that meets it. */
static MsSpan method_key(Builder *b, const MsMethodEntry *entry) {
  MsCheckProgram *program = b->program;
  const MsTyKind kind = ms_ty_kind(&program->types, entry->receiver);
  if (kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE) {
    for (uint32_t module = 0; module < program->user_modules; module++) {
      const MsModule *tree = program->modules.ptr[module].tree;
      for (uint32_t at = 0; at < tree->ndecls; at++) {
        const MsDecl *decl = tree->decls[at];
        MsName declared = 0;
        if (decl->kind != MS_D_INTERFACE || decl->synthetic || !ms_check_declared_name(decl, &declared)) {
          continue;
        }
        const MsSymbolId *found = ms_scope_get(&program->modules.ptr[module].scope, declared);
        if (found == NULL || program->symbols.ptr[*found].decl != decl || program->symbols.ptr[*found].ty == MS_TY_NONE) {
          continue;
        }
        const MsSymbol *symbol = &program->symbols.ptr[*found];
        const MsDef *def = symbol->def == 0 ? NULL : ms_defs_get(&program->defs, symbol->def);
        for (size_t op = 0; def != NULL && op < def->operations.len; op++) {
          const MsOperation *operation = &def->operations.ptr[op];
          if (operation->name != entry->name) {
            continue;
          }
          const MsTy shown = ms_check_operation_type(program, symbol->ty, operation, entry->receiver);
          const size_t count = ms_ty_param_count(&program->types, entry->ty);
          if (shown != entry->ty || ms_ty_param_count(&program->types, operation->ty) != count) {
            continue;
          }
          bool same = true;
          for (size_t index = 0; index < count; index++) {
            same = same && ms_ty_params(&program->types, entry->ty)[index].name == ms_ty_params(&program->types, operation->ty)[index].name;
          }
          if (same) {
            return operation_key(b, *found, operation->name);
          }
        }
      }
    }
  }
  return ms_message_format(b->arena, "method:%S:%u", module_file(b, entry->module), entry->source->pos.offset);
}

/* ---- declarations ---- */

static MsSymbolId declared_symbol(const Builder *b, uint32_t module, const MsDecl *decl) {
  MsName name = 0;
  if (!ms_check_declared_name(decl, &name)) {
    return 0;
  }
  const MsSymbolId *found = ms_scope_get(&b->program->modules.ptr[module].scope, name);
  return found != NULL && b->program->symbols.ptr[*found].decl == decl ? *found : 0;
}

static void declare_symbols(Builder *b, uint32_t module) {
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsSpan source = source_of(b, module);
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    const MsSymbolId id = declared_symbol(b, module, decl);
    if (id == 0 || (decl->synthetic && decl->kind == MS_D_INTERFACE)) {
      continue;
    }
    const MsSymbol *symbol = &b->program->symbols.ptr[id];
    const MsSpan name = name_text(b, symbol->name);
    const MsSpan key = symbol_key(b, id);
    const MsTy value = decl->kind == MS_D_CONST && symbol->ty == MS_TY_NONE
                           ? ms_facts_type(&b->program->modules.ptr[module].facts, decl->u.konst.value->id)
                           : symbol->ty;
    add(b, key, name, module, header(source, decl->pos.offset, name), true, false, value, id, false);
    if (symbol->ty == MS_TY_NONE || symbol->def == 0) {
      continue;
    }
    const MsDef *def = ms_defs_get(&b->program->defs, symbol->def);
    if (decl->kind == MS_D_TYPE) {
      for (uint32_t index = 0; index < decl->u.type.fields.len; index++) {
        const MsParam *field = decl->u.type.fields.ptr[index];
        for (size_t slot = 0; slot < def->fields.len; slot++) {
          if (def->fields.ptr[slot].name == field->name) {
            add(b, ms_message_format(b->arena, "field:%S:%S", key, name_text(b, field->name)), name_text(b, field->name), module,
                field->pos.offset, true, false, def->fields.ptr[slot].ty, 0, false);
          }
        }
      }
    }
    if (decl->kind == MS_D_ENUM) {
      for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
        const MsCase *kase = decl->u.enumeration.cases.ptr[index];
        add(b, ms_message_format(b->arena, "case:%S:%S", key, name_text(b, kase->name)), name_text(b, kase->name), module,
            kase->pos.offset, true, false, symbol->ty, 0, false);
      }
    }
    if (decl->kind == MS_D_INTERFACE) {
      for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
        const MsMethod *method = decl->u.iface.methods.ptr[index];
        for (size_t op = 0; op < def->operations.len; op++) {
          if (def->operations.ptr[op].name != method->func.name) {
            continue;
          }
          const MsSpan method_name = name_text(b, method->func.name);
          add(b, operation_key(b, id, method->func.name), method_name, module, header(source, method->pos.offset, method_name),
              true, false, def->operations.ptr[op].ty, 0, true);
        }
      }
    }
  }
  for (uint32_t index = 0; index < tree->nimports; index++) {
    const MsImport *import = &tree->imports[index];
    const MsSymbolId *found = ms_scope_get(&b->program->modules.ptr[module].imports, import->name);
    if (found != NULL && *found != 0) {
      add(b, symbol_key(b, *found), name_text(b, import->name), module, import->name_pos.offset, false, false,
          b->program->symbols.ptr[*found].ty, *found, false);
    }
  }
}

/* ---- parameters and bindings ---- */

/* The identity of every parameter, field and lambda parameter, by the node that declares it. */
static void name_parameters(Builder *b, uint32_t module) {
  const MsModule *tree = b->program->modules.ptr[module].tree;
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->kind == MS_D_FN) {
      for (uint32_t index = 0; index < decl->u.fn.params.len; index++) {
        b->param_key[module][decl->u.fn.params.ptr[index]->id] =
            ms_message_format(b->arena, "parameter:%S:%u:%u", module_file(b, module), decl->pos.offset, index);
      }
    } else if (decl->kind == MS_D_TYPE) {
      const MsSymbolId id = declared_symbol(b, module, decl);
      for (uint32_t index = 0; id != 0 && index < decl->u.type.fields.len; index++) {
        const MsParam *field = decl->u.type.fields.ptr[index];
        b->param_key[module][field->id] = ms_message_format(b->arena, "field:%S:%S", symbol_key(b, id), name_text(b, field->name));
      }
    }
    const MsMethod *const *methods = NULL;
    uint32_t count = 0;
    if (decl->kind == MS_D_INTERFACE) {
      methods = (const MsMethod *const *)decl->u.iface.methods.ptr;
      count = decl->u.iface.methods.len;
    } else if (decl->kind == MS_D_IMPL) {
      methods = (const MsMethod *const *)decl->u.impl.methods.ptr;
      count = decl->u.impl.methods.len;
    }
    for (uint32_t method = 0; method < count; method++) {
      const MsParams params = methods[method]->func.params;
      for (uint32_t index = 0; index < params.len; index++) {
        b->param_key[module][params.ptr[index]->id] =
            ms_message_format(b->arena, "parameter:%S:%u:%u", module_file(b, module), methods[method]->pos.offset, index);
      }
    }
  }
}

/* The identity of the binding a ref names. */
static MsSpan binding_key(const Builder *b, const MsRef *ref) {
  if (ref->kind == MS_REF_PARAM) {
    const MsSpan known = ref->decl.node < b->program->modules.ptr[ref->decl.module].tree->node_count
                             ? b->param_key[ref->decl.module][ref->decl.node]
                             : (MsSpan){0};
    if (known.len != 0) {
      return known;
    }
  }
  return ms_message_format(b->arena, "binding:%u:%u:%u", ref->decl.module, ref->decl.node, ref->local);
}

static void declare_local(Builder *b, MsName name, MsPos pos, uint32_t offset, const MsRef *ref, MsTy ty) {
  (void)pos;
  add(b, binding_key(b, ref), name_text(b, name), b->module, offset, true, false, ty, 0, false);
}

static void declare_pattern(Builder *b, const MsPattern *pattern) {
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  const MsRef *ref = ms_facts_ref(facts, pattern->id);
  if (pattern->kind == MS_P_NAME && ref != NULL && ref->kind == MS_REF_LOCAL) {
    declare_local(b, pattern->u.name, pattern->pos, pattern->pos.offset, ref, ms_facts_type(facts, pattern->id));
  } else if (pattern->kind == MS_P_LIST) {
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      declare_pattern(b, pattern->u.list.ptr[index]);
    }
  } else if (pattern->kind == MS_P_TYPE) {
    for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
      declare_pattern(b, pattern->u.fields.ptr[index].pattern);
    }
  }
}

static void bindings_stmt(void *context, const MsStmt *stmt) {
  Builder *b = context;
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  if (stmt->kind == MS_S_BIND) {
    declare_pattern(b, stmt->u.bind.pattern);
  } else if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL) {
    declare_pattern(b, stmt->u.branch.binding);
  } else if (stmt->kind == MS_S_FOR) {
    const MsRef *ref = ms_facts_ref(facts, stmt->id);
    if (ref != NULL && ref->kind == MS_REF_LOCAL) {
      const MsSpan name = name_text(b, stmt->u.each.name);
      declare_local(b, stmt->u.each.name, stmt->pos, header(source_of(b, b->module), stmt->pos.offset, name), ref,
                    ms_facts_type(facts, stmt->id));
    }
  }
}

/* The type the checker gave the local `name` declared at `offset` of the module being walked. */
static MsTy record_type(const Builder *b, MsName name, uint32_t offset) {
  for (size_t index = 0; index < b->program->bindings.len; index++) {
    const MsLocalRecord *record = &b->program->bindings.ptr[index];
    if (record->module == b->module && record->pos.offset == offset && record->name == name) {
      return record->ty;
    }
  }
  return MS_TY_NONE;
}

static void bindings_expr(void *context, const MsExpr *expr) {
  Builder *b = context;
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  if (expr->kind == MS_E_LAMBDA) {
    for (uint32_t index = 0; index < expr->u.lambda.params.len; index++) {
      const MsParam *param = expr->u.lambda.params.ptr[index];
      const MsRef ref = {.kind = MS_REF_PARAM, .decl = {b->module, param->id}};
      declare_local(b, param->name, param->pos, param->pos.offset, &ref, ms_facts_type(facts, param->id));
    }
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      const MsArm *arm = expr->u.match.arms.ptr[index];
      const MsRef *first = ms_facts_ref(facts, arm->id);
      for (uint32_t at = 0; first != NULL && at < arm->bindings.len; at++) {
        const MsRef ref = {.kind = MS_REF_LOCAL, .decl = {b->module, arm->id}, .local = first->local + at};
        const MsSpan name = name_text(b, arm->bindings.ptr[at].name);
        if (ms_span_is_text(name, "_")) {
          continue;
        }
        add(b, binding_key(b, &ref), name, b->module, header(source_of(b, b->module), arm->pos.offset, name), true, false,
            record_type(b, arm->bindings.ptr[at].name, arm->pos.offset), 0, false);
      }
    }
  }
}

static void declare_parameters(Builder *b, uint32_t module, const MsParams params, uint32_t first_index) {
  const MsFacts *facts = &b->program->modules.ptr[module].facts;
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    const MsRef ref = {.kind = MS_REF_PARAM, .decl = {module, param->id}};
    add(b, binding_key(b, &ref), name_text(b, param->name), module, param->pos.offset, true, false, ms_facts_type(facts, param->id), 0,
        false);
    (void)first_index;
  }
}

static void declare_bindings(Builder *b, uint32_t module) {
  b->module = module;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsVisitor visitor = {.ctx = b, .stmt = bindings_stmt, .expr = bindings_expr};
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->kind == MS_D_FN) {
      declare_parameters(b, module, decl->u.fn.params, 0);
    } else if (decl->kind == MS_D_INTERFACE || decl->kind == MS_D_IMPL) {
      const bool iface = decl->kind == MS_D_INTERFACE;
      const uint32_t count = iface ? decl->u.iface.methods.len : decl->u.impl.methods.len;
      for (uint32_t method = 0; method < count; method++) {
        declare_parameters(b, module, (iface ? decl->u.iface.methods.ptr[method] : decl->u.impl.methods.ptr[method])->func.params, 0);
      }
    }
    ms_walk_decl(&visitor, decl);
  }
}

static void declare_methods(Builder *b) {
  for (size_t index = 0; index < b->program->methods.len; index++) {
    const MsMethodEntry *entry = &b->program->methods.ptr[index];
    if (entry->module >= b->program->user_modules) {
      continue;
    }
    const MsSpan name = name_text(b, entry->source->func.name);
    add(b, method_key(b, entry), name, entry->module, header(source_of(b, entry->module), entry->source->pos.offset, name), true,
        false, entry->ty, 0, true);
  }
}

/* ---- written types ---- */

static void type_site(Builder *b, const MsTypeRef *type) {
  type_sites_push(b->arena, b->sink, (TypeSite){.id = type->id, .offset = type->pos.offset, .name = type->name, .named = type->kind == MS_TYPE_NAMED});
  if (type->kind == MS_TYPE_NAMED) {
    for (uint32_t index = 0; index < type->args.len; index++) {
      type_site(b, type->args.ptr[index]);
    }
  } else {
    for (uint32_t index = 0; index < type->params.len; index++) {
      if (type->params.ptr[index]->ty != NULL) {
        type_site(b, type->params.ptr[index]->ty);
      }
    }
    if (type->result != NULL) {
      type_site(b, type->result);
    }
  }
}

/* A written type that names a nominal type is an occurrence of it. */
static void emit_type_sites(Builder *b, const TypeSites *sites) {
  for (size_t index = 0; index < sites->len; index++) {
    const TypeSite *site = &sites->ptr[index];
    const MsTy resolved = site->id < b->program->modules.ptr[b->module].tree->node_count ? b->written[b->module][site->id] : MS_TY_NONE;
    const MsSymbolId symbol = site->named ? type_symbol(b, resolved) : 0;
    if (symbol != 0) {
      add(b, symbol_key(b, symbol), name_text(b, site->name), b->module, site->offset, false, false, resolved, symbol, false);
    }
  }
}

static void param_sites(Builder *b, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->ty != NULL) {
      type_site(b, params.ptr[index]->ty);
    }
  }
}

static void type_param_sites(Builder *b, MsTypeParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    for (uint32_t bound = 0; bound < params.ptr[index]->bounds.len; bound++) {
      type_site(b, params.ptr[index]->bounds.ptr[bound]);
    }
    if (params.ptr[index]->def != NULL) {
      type_site(b, params.ptr[index]->def);
    }
  }
}

static void func_sites(Builder *b, const MsFunc *func) {
  type_param_sites(b, func->type_params);
  param_sites(b, func->params);
  if (func->result != NULL) {
    type_site(b, func->result);
  }
}

static void body_types_stmt(void *context, const MsStmt *stmt) {
  Builder *b = context;
  if (stmt->kind == MS_S_BIND && stmt->u.bind.ty != NULL) {
    type_site(b, stmt->u.bind.ty);
  }
}

static void arm_path_types(Builder *b, const MsExpr *path) {
  if (path->kind == MS_E_APPLY) {
    for (uint32_t index = 0; index < path->u.apply.types.len; index++) {
      type_site(b, path->u.apply.types.ptr[index]);
    }
    arm_path_types(b, path->u.apply.left);
  } else if (path->kind == MS_E_MEMBER) {
    arm_path_types(b, path->u.member.left);
  }
}

static void body_types_expr(void *context, const MsExpr *expr) {
  Builder *b = context;
  if (expr->kind == MS_E_APPLY) {
    for (uint32_t index = 0; index < expr->u.apply.types.len; index++) {
      type_site(b, expr->u.apply.types.ptr[index]);
    }
  } else if (expr->kind == MS_E_LAMBDA) {
    param_sites(b, expr->u.lambda.params);
    if (expr->u.lambda.result != NULL) {
      type_site(b, expr->u.lambda.result);
    }
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      arm_path_types(b, expr->u.match.arms.ptr[index]->path);
    }
  }
}

static void declare_types(Builder *b, uint32_t module) {
  b->module = module;
  TypeSites sites = {0};
  b->sink = &sites;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsVisitor visitor = {.ctx = b, .stmt = body_types_stmt, .expr = body_types_expr};
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    switch ((MsDeclKind)decl->kind) {
    case MS_D_FN:
      func_sites(b, &decl->u.fn);
      break;
    case MS_D_CONST:
      if (decl->u.konst.ty != NULL) {
        type_site(b, decl->u.konst.ty);
      }
      break;
    case MS_D_TYPE:
      type_param_sites(b, decl->u.type.type_params);
      param_sites(b, decl->u.type.fields);
      break;
    case MS_D_ENUM:
      type_param_sites(b, decl->u.enumeration.type_params);
      for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
        param_sites(b, decl->u.enumeration.cases.ptr[index]->fields);
      }
      break;
    case MS_D_ALIAS:
      type_param_sites(b, decl->u.alias.type_params);
      for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
        type_site(b, decl->u.alias.targets.ptr[index]);
      }
      break;
    case MS_D_INTERFACE:
      type_param_sites(b, decl->u.iface.type_params);
      for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
        func_sites(b, &decl->u.iface.methods.ptr[index]->func);
      }
      break;
    case MS_D_IMPL:
      /* The first method of a receiver form writes it as a type; the rest are folded into that one. */
      if (b->folded_into[module][at] == at) {
        type_site(b, decl->u.impl.receiver);
      }
      for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
        func_sites(b, &decl->u.impl.methods.ptr[index]->func);
      }
      break;
    case MS_D_TEST:
      break;
    }
    ms_walk_decl(&visitor, decl);
  }
  emit_type_sites(b, &sites);
}

/* ---- type parameters ---- */

/* The written name declares a type parameter and every use inside its declaration resolves to it, so they navigate
 * like locals. */
typedef struct ParamSite {
  MsName name;
  uint32_t offset;   /* the written name */
  uint32_t declared; /* the declaring name, which identifies the parameter */
  bool declaration;
  bool has_checked;  /* a use whose resolution the checker recorded */
  uint32_t checked;
} ParamSite;

MS_AVEC(ParamSites, param_sites_list, ParamSite)

enum { SCOPE_MAX = 48 };

typedef struct ParamScope {
  MsName name[SCOPE_MAX];
  uint32_t declared[SCOPE_MAX];
  size_t len;
} ParamScope;

static void scope_push(ParamScope *scope, MsName name, uint32_t declared) {
  if (scope->len < SCOPE_MAX) {
    scope->name[scope->len] = name;
    scope->declared[scope->len] = declared;
    scope->len++;
  }
}

static void scope_declare(Builder *b, ParamScope *scope, ParamSites *out, MsName name, uint32_t offset) {
  scope_push(scope, name, offset);
  param_sites_list_push(b->arena, out, (ParamSite){.name = name, .offset = offset, .declared = offset, .declaration = true});
}

static void scope_declare_all(Builder *b, ParamScope *scope, ParamSites *out, MsTypeParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    scope_declare(b, scope, out, params.ptr[index]->name, params.ptr[index]->pos.offset);
  }
}

static void scope_uses(Builder *b, const ParamScope *scope, const TypeSites *sites, size_t from, bool checked, ParamSites *out) {
  for (size_t index = from; index < sites->len; index++) {
    const TypeSite *site = &sites->ptr[index];
    for (size_t at = scope->len; site->named && at > 0; at--) {
      if (scope->name[at - 1] == site->name) {
        param_sites_list_push(b->arena, out, (ParamSite){.name = site->name, .offset = site->offset, .declared = scope->declared[at - 1],
                                                          .has_checked = checked, .checked = site->id});
        break;
      }
    }
  }
}

static void collect_type_params(Builder *b, MsTypeParams params) {
  type_param_sites(b, params);
}

/* The type sites of one function: its signature and the annotations in its body. */
static TypeSites function_sites(Builder *b, const MsFunc *func) {
  TypeSites sites = {0};
  TypeSites *saved = b->sink;
  b->sink = &sites;
  func_sites(b, func);
  const MsVisitor visitor = {.ctx = b, .stmt = body_types_stmt, .expr = body_types_expr};
  ms_walk_callable(&visitor, func->params, func->body);
  b->sink = saved;
  return sites;
}

static void method_scopes(Builder *b, const ParamScope *outer, MsMethod *const *methods, uint32_t count, ParamSites *out) {
  for (uint32_t index = 0; index < count; index++) {
    ParamScope scope = *outer;
    TypeSites receiver = {0};
    TypeSites *saved = b->sink;
    b->sink = &receiver;
    for (uint32_t at = 0; at < methods[index]->receiver_args.len; at++) {
      type_site(b, methods[index]->receiver_args.ptr[at]);
    }
    b->sink = saved;
    scope_uses(b, &scope, &receiver, 0, false, out);
    scope_declare_all(b, &scope, out, methods[index]->func.type_params);
    const TypeSites own = function_sites(b, &methods[index]->func);
    scope_uses(b, &scope, &own, 0, true, out);
  }
}

/* The type a module declares as `name`, for the parameters a receiver writes. */
static MsTypeParams declared_type_params(const MsModule *tree, MsName name, bool *found) {
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->kind == MS_D_TYPE && decl->u.type.name == name) {
      *found = true;
      return decl->u.type.type_params;
    }
    if (decl->kind == MS_D_ENUM && decl->u.enumeration.name == name) {
      *found = true;
      return decl->u.enumeration.type_params;
    }
  }
  *found = false;
  return (MsTypeParams){0};
}

static void type_parameter_sites(Builder *b, uint32_t module, ParamSites *out) {
  b->module = module;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  ParamScope *scopes = MS_ARENA_NEW_ARRAY(b->arena, ParamScope, tree->ndecls + 1);
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->synthetic && decl->kind == MS_D_INTERFACE) {
      continue;
    }
    ParamScope scope = {0};
    TypeSites sites = {0};
    b->sink = &sites;
    const bool folded = decl->kind == MS_D_IMPL && b->folded_into[module][at] != at;
    if (folded) {
      scope = scopes[b->folded_into[module][at]];
    }
    switch (folded ? MS_D_TEST : (MsDeclKind)decl->kind) {
    case MS_D_FN: {
      scope_declare_all(b, &scope, out, decl->u.fn.type_params);
      const TypeSites own = function_sites(b, &decl->u.fn);
      scope_uses(b, &scope, &own, 0, true, out);
      break;
    }
    case MS_D_TYPE:
      scope_declare_all(b, &scope, out, decl->u.type.type_params);
      collect_type_params(b, decl->u.type.type_params);
      param_sites(b, decl->u.type.fields);
      break;
    case MS_D_ENUM:
      scope_declare_all(b, &scope, out, decl->u.enumeration.type_params);
      collect_type_params(b, decl->u.enumeration.type_params);
      for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
        param_sites(b, decl->u.enumeration.cases.ptr[index]->fields);
      }
      break;
    case MS_D_ALIAS:
      scope_declare_all(b, &scope, out, decl->u.alias.type_params);
      collect_type_params(b, decl->u.alias.type_params);
      for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
        type_site(b, decl->u.alias.targets.ptr[index]);
      }
      break;
    case MS_D_INTERFACE:
      scope_declare_all(b, &scope, out, decl->u.iface.type_params);
      collect_type_params(b, decl->u.iface.type_params);
      break;
    case MS_D_IMPL: {
      /* The receiver's bare arguments name the parameters of the type it extends (`fn Gen[T].map` uses `T` of
       * `type Gen[T]`); a receiver whose type is declared elsewhere declares them here. */
      TypeSites receiver = {0};
      b->sink = &receiver;
      type_site(b, decl->u.impl.receiver);
      b->sink = &sites;
      if (decl->u.impl.receiver->kind == MS_TYPE_NAMED) {
        bool found = false;
        const MsTypeParams declared = declared_type_params(tree, decl->u.impl.receiver->name, &found);
        for (uint32_t index = 0; index < decl->u.impl.receiver->args.len; index++) {
          const MsTypeRef *arg = decl->u.impl.receiver->args.ptr[index];
          if (arg->kind != MS_TYPE_NAMED || arg->args.len != 0) {
            continue;
          }
          if (found && index < declared.len) {
            if (declared.ptr[index]->name == arg->name) {
              scope_push(&scope, arg->name, declared.ptr[index]->pos.offset);
            }
          } else if (!found || index >= declared.len) {
            scope_declare(b, &scope, out, arg->name, arg->pos.offset);
          }
        }
      }
      scope_uses(b, &scope, &receiver, 1, true, out);
      for (uint32_t index = 0; index < decl->u.impl.bounds.len; index++) {
        TypeSites bounds = {0};
        b->sink = &bounds;
        for (uint32_t bound = 0; bound < decl->u.impl.bounds.ptr[index]->bounds.len; bound++) {
          type_site(b, decl->u.impl.bounds.ptr[index]->bounds.ptr[bound]);
        }
        b->sink = &sites;
        scope_uses(b, &scope, &bounds, 0, true, out);
      }
      break;
    }
    case MS_D_CONST:
    case MS_D_TEST:
      break;
    }
    scopes[at] = scope;
    scope_uses(b, &scope, &sites, 0, true, out);
    if (decl->kind == MS_D_INTERFACE) {
      method_scopes(b, &scope, decl->u.iface.methods.ptr, decl->u.iface.methods.len, out);
    } else if (decl->kind == MS_D_IMPL) {
      method_scopes(b, &scope, decl->u.impl.methods.ptr, decl->u.impl.methods.len, out);
    }
  }
}

MS_MAP_DEFINE(OffsetTypes, offset_types, uint32_t, MsTy, ms_hash_u32_key, ms_equal_u32_key)

static void declare_type_parameters(Builder *b, uint32_t module) {
  ParamSites found = {0};
  type_parameter_sites(b, module, &found);
  b->module = module;
  const MsFacts *facts = &b->program->modules.ptr[module].facts;
  (void)facts;
  OffsetTypes first = {0};
  MsTy *own = MS_ARENA_NEW_ARRAY(b->arena, MsTy, found.len + 1);
  bool *skip = MS_ARENA_NEW_ARRAY(b->arena, bool, found.len + 1);
  for (size_t index = 0; index < found.len; index++) {
    const ParamSite *site = &found.ptr[index];
    if (site->has_checked) {
      const MsTy ty = site->checked < b->program->modules.ptr[module].tree->node_count ? b->written[module][site->checked] : MS_TY_NONE;
      if (ty == MS_TY_NONE || ms_ty_kind(&b->program->types, ty) != MS_TY_VARIABLE) {
        skip[index] = true;
        continue;
      }
      own[index] = ty;
      if (offset_types_get(&first, site->declared) == NULL) {
        offset_types_put(&first, site->declared, ty);
      }
    }
  }
  for (size_t index = 0; index < found.len; index++) {
    const ParamSite *site = &found.ptr[index];
    if (skip[index]) {
      continue;
    }
    MsTy ty = own[index];
    if (ty == MS_TY_NONE) {
      const MsTy *known = offset_types_get(&first, site->declared);
      ty = known == NULL ? MS_TY_NONE : *known;
    }
    add(b, ms_message_format(b->arena, "binding:typeparam:%S:%u", module_file(b, module), site->declared), name_text(b, site->name),
        module, site->offset, site->declaration, false, ty, 0, false);
  }
  offset_types_free(&first);
}

/* ---- uses ---- */

static const MsCall *call_of(const Builder *b, const MsExpr *expr) {
  return ms_facts_call(&b->program->modules.ptr[b->module].facts, expr->id);
}

static void use_name(Builder *b, const MsExpr *expr, const MsRef *ref, MsTy ty, bool write) {
  const MsSpan name = name_text(b, expr->u.sym);
  if (ref->kind == MS_REF_LOCAL || ref->kind == MS_REF_PARAM) {
    add(b, binding_key(b, ref), name, b->module, expr->pos.offset, false, write, ty, 0, false);
    return;
  }
  if (ref->kind == MS_REF_CASE) {
    const MsSymbolId parent = type_symbol(b, ref->owner);
    if (parent == 0) {
      return;
    }
    if (b->program->symbols.ptr[parent].module >= b->program->user_modules) {
      add(b, ms_message_format(b->arena, "native:%S", name), name, b->module, expr->pos.offset, false, write, ty, 0, false);
    } else {
      add(b, ms_message_format(b->arena, "case:%S:%S", symbol_key(b, parent), name), name, b->module, expr->pos.offset, false, false,
          ref->owner, 0, false);
    }
    return;
  }
  const MsSymbolId symbol = symbol_of_ref(b, ref);
  if (symbol != 0 && (ref->kind == MS_REF_FUNCTION || ref->kind == MS_REF_CONSTANT || ref->kind == MS_REF_TYPE || ref->kind == MS_REF_NATIVE)) {
    add(b, symbol_key(b, symbol), name, b->module, expr->pos.offset, false, write, ty, symbol, false);
  }
}

/* The operation a native method is: the interface of the standard module whose method node the ref names. */
static MsSpan native_operation_key(const Builder *b, const MsRef *ref, MsName name) {
  for (size_t index = 1; index < b->program->symbols.len; index++) {
    const MsSymbol *symbol = &b->program->symbols.ptr[index];
    if (symbol->module != ref->decl.module || symbol->decl == NULL || symbol->decl->kind != MS_D_INTERFACE) {
      continue;
    }
    for (uint32_t at = 0; at < symbol->decl->u.iface.methods.len; at++) {
      if (symbol->decl->u.iface.methods.ptr[at]->id == ref->decl.node) {
        return operation_key(b, (MsSymbolId)index, name);
      }
    }
  }
  return (MsSpan){0};
}

static void use_member(Builder *b, const MsExpr *expr, const MsRef *ref, MsTy ty, bool write) {
  const MsSpan name = name_text(b, expr->u.member.name);
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  if (ref->kind == MS_REF_FIELD) {
    const MsTy receiver = ms_facts_type(facts, expr->u.member.left->id);
    const MsSymbolId parent = ms_ty_kind(&b->program->types, receiver) == MS_TY_TYPE ? type_symbol(b, receiver) : 0;
    if (parent != 0) {
      add(b, ms_message_format(b->arena, "field:%S:%S", symbol_key(b, parent), name), name, b->module, expr->pos.offset, false, write,
          ty, 0, false);
    }
  } else if (ref->kind == MS_REF_CASE) {
    const MsSymbolId parent = type_symbol(b, ref->owner);
    if (parent != 0) {
      add(b, ms_message_format(b->arena, "case:%S:%S", symbol_key(b, parent), name), name, b->module, expr->pos.offset, false, false, ty, 0,
          false);
    }
  } else if (ref->kind == MS_REF_METHOD || ref->kind == MS_REF_NATIVE || ref->kind == MS_REF_OPERATION) {
    MsSpan key = {0};
    if (ref->kind == MS_REF_OPERATION) {
      key = native_operation_key(b, ref, expr->u.member.name);
    } else {
      const MsMethodEntry *entry = method_entry(b, ref->decl.module, ref->decl.node);
      key = entry != NULL ? method_key(b, entry) : native_operation_key(b, ref, expr->u.member.name);
    }
    add(b, key, name, b->module, expr->pos.offset, false, write, ty, 0, true);
  }
}

static const MsExpr *peel_apply(const MsExpr *expr) {
  while (expr->kind == MS_E_APPLY) {
    expr = expr->u.apply.left;
  }
  return expr;
}

/* The constructor a call builds: its case, its type, and the labels of its arguments. */
static void use_call(Builder *b, const MsExpr *expr, MsTy ty) {
  const MsCall *call = call_of(b, expr);
  if (call == NULL) {
    return;
  }
  const MsExpr *callee = expr->u.call.callee;
  if (call->callee.kind == MS_REF_CASE) {
    const MsSymbolId parent = type_symbol(b, call->callee.owner);
    const MsExpr *written = peel_apply(callee);
    const bool member = written->kind == MS_E_MEMBER;
    if (parent != 0 && (member || written->kind == MS_E_NAME)) {
      const MsName case_name = member ? written->u.member.name : written->u.sym;
      add(b, ms_message_format(b->arena, "case:%S:%S", symbol_key(b, parent), name_text(b, case_name)), name_text(b, case_name),
          b->module, written->pos.offset, false, false, ty, 0, false);
      if (!member) {
        /* A constructor named bare (`ok`, `Node`) is also a symbol of its own in the oracle's index. */
        add(b, ms_message_format(b->arena, "native:%S", name_text(b, case_name)), name_text(b, case_name), b->module,
            written->pos.offset, false, false, ty, 0, false);
      }
      const MsExpr *root = member ? peel_apply(written->u.member.left) : NULL;
      if (root != NULL && root->kind == MS_E_NAME) {
        add(b, symbol_key(b, parent), name_text(b, root->u.sym), b->module, root->pos.offset, false, false, ty, parent, false);
      }
    }
    return;
  }
  if (call->callee.kind == MS_REF_TYPE) {
    MsSymbolId parent = symbol_of_ref(b, &call->callee);
    parent = parent != 0 ? parent : type_symbol(b, ty); /* a native type has no declaration node */
    const MsDef *def = parent == 0 || b->program->symbols.ptr[parent].def == 0 ? NULL : ms_defs_get(&b->program->defs, b->program->symbols.ptr[parent].def);
    const MsExpr *left = peel_apply(callee);
    if (left->kind == MS_E_NAME && parent != 0) {
      add(b, symbol_key(b, parent), name_text(b, left->u.sym), b->module, left->pos.offset, false, false, ty, parent, false);
    }
    for (uint32_t index = 0; def != NULL && index < expr->u.call.args.len; index++) {
      const MsArg *arg = &expr->u.call.args.ptr[index];
      for (size_t slot = 0; arg->has_name && slot < def->fields.len; slot++) {
        if (def->fields.ptr[slot].name == arg->name) {
          const size_t count = ms_ty_arg_count(&b->program->types, ty) < def->variables.len ? ms_ty_arg_count(&b->program->types, ty)
                                                                                           : def->variables.len;
          const MsTy field = ms_ty_subst(&b->program->types, def->fields.ptr[slot].ty, def->variables.ptr,
                                         ms_ty_args(&b->program->types, ty), count);
          add(b, ms_message_format(b->arena, "field:%S:%S", symbol_key(b, parent), name_text(b, arg->name)), name_text(b, arg->name),
              b->module, arg->pos.offset, false, false, field, 0, false);
        }
      }
    }
    return;
  }
  /* A prelude constructor (`ok`, `error`, `some`) builds a case of the type it returns. */
  const MsSymbolId parent = call->constructor ? type_symbol(b, ty) : 0;
  const MsExpr *named = peel_apply(callee);
  if (parent != 0 && named->kind == MS_E_NAME) {
    add(b, ms_message_format(b->arena, "case:%S:%S", symbol_key(b, parent), name_text(b, named->u.sym)), name_text(b, named->u.sym),
        b->module, named->pos.offset, false, false, ty, 0, false);
  }
}

/* A match path names a case of the scrutinee's alternative: it bypasses expression inference, so the case comes from
 * the scrutinee's type. */
static void match_case(Builder *b, const MsExpr *scrutinee, const MsExpr *path) {
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  const MsTy ty = ms_facts_type(facts, scrutinee->id);
  if (ty == MS_TY_NONE || ms_ty_kind(&b->program->types, ty) != MS_TY_ALTERNATIVE) {
    return;
  }
  const MsSymbolId parent = type_symbol(b, ty);
  if (parent == 0) {
    return;
  }
  MsName name = 0;
  if (path->kind == MS_E_NAME) {
    name = path->u.sym;
  } else if (path->kind == MS_E_MEMBER) {
    const MsExpr *qualifier = peel_apply(path->u.member.left);
    const MsRef *ref = qualifier->kind == MS_E_NAME ? ms_facts_ref(facts, qualifier->id) : NULL;
    if (ref == NULL || symbol_of_ref(b, ref) != parent) {
      return;
    }
    name = path->u.member.name;
  } else {
    return;
  }
  const MsDef *def = ms_defs_get(&b->program->defs, b->program->symbols.ptr[parent].def);
  for (size_t index = 0; index < def->cases.len; index++) {
    if (def->cases.ptr[index].name == name) {
      add(b, ms_message_format(b->arena, "case:%S:%S", symbol_key(b, parent), name_text(b, name)), name_text(b, name), b->module,
          path->pos.offset, false, false, ty, 0, false);
      return;
    }
  }
}

/* Argument labels resolve to the parameters of a callee with a body, whichever module declares it. */
static void use_labels(Builder *b, const MsExpr *expr) {
  const MsCall *call = call_of(b, expr);
  if (call == NULL || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD) || call->callee.decl.node == 0) {
    return;
  }
  const uint32_t home = call->callee.decl.module;
  const MsParams *params = NULL;
  uint32_t declared_at = 0;
  if (call->callee.kind == MS_REF_FUNCTION) {
    const MsModule *tree = b->program->modules.ptr[home].tree;
    for (uint32_t at = 0; at < tree->ndecls; at++) {
      if (tree->decls[at]->id == call->callee.decl.node && tree->decls[at]->kind == MS_D_FN) {
        params = &tree->decls[at]->u.fn.params;
        declared_at = tree->decls[at]->pos.offset;
      }
    }
  } else {
    const MsMethodEntry *entry = method_entry(b, home, call->callee.decl.node);
    params = entry == NULL ? NULL : &entry->source->func.params;
    declared_at = entry == NULL ? 0 : entry->source->pos.offset;
  }
  const MsFacts *owner = &b->program->modules.ptr[home].facts;
  for (uint32_t index = 0; params != NULL && index < expr->u.call.args.len; index++) {
    const MsArg *arg = &expr->u.call.args.ptr[index];
    for (uint32_t at = 0; arg->has_name && at < params->len; at++) {
      if (params->ptr[at]->name == arg->name) {
        add(b, ms_message_format(b->arena, "parameter:%S:%u:%u", module_file(b, home), declared_at, at), name_text(b, arg->name),
            b->module, arg->pos.offset, false, false, ms_facts_type(owner, params->ptr[at]->id), 0, false);
      }
    }
  }
}

static void uses_expr(void *context, const MsExpr *expr) {
  Builder *b = context;
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  const MsRef *ref = ms_facts_ref(facts, expr->id);
  const MsTy ty = ms_facts_type(facts, expr->id);
  const bool write = b->assigned[b->module][expr->id];
  if (expr->kind == MS_E_NAME && ref != NULL) {
    use_name(b, expr, ref, ty, write);
  } else if (expr->kind == MS_E_MEMBER && ref != NULL) {
    use_member(b, expr, ref, ty, write);
  } else if (expr->kind == MS_E_CALL) {
    use_call(b, expr, ty);
    use_labels(b, expr);
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      const MsArm *arm = expr->u.match.arms.ptr[index];
      const MsTy scrutinee = ms_facts_type(facts, expr->u.match.scrutinee->id);
      const bool optional = arm->bare && ms_ty_is(&b->program->types, scrutinee, MS_BUILTIN_Optional);
      if (!optional && !arm->from_if) {
        match_case(b, expr->u.match.scrutinee, arm->path);
      }
    }
  }
}

static void uses_stmt(void *context, const MsStmt *stmt) {
  Builder *b = context;
  const MsFacts *facts = &b->program->modules.ptr[b->module].facts;
  if (stmt->kind != MS_S_ASSIGN) {
    return;
  }
  if (stmt->u.assign.target != NULL) {
    b->assigned[b->module][stmt->u.assign.target->id] = true;
    return;
  }
  const MsRef *ref = ms_facts_ref(facts, stmt->id);
  if (ref != NULL && (ref->kind == MS_REF_LOCAL || ref->kind == MS_REF_PARAM)) {
    add(b, binding_key(b, ref), name_text(b, stmt->u.assign.name), b->module, stmt->pos.offset, false, true, ms_facts_type(facts, stmt->id), 0,
        false);
  }
}

static void declare_uses(Builder *b, uint32_t module) {
  b->module = module;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsVisitor visitor = {.ctx = b, .stmt = uses_stmt, .expr = uses_expr};
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    ms_walk_decl(&visitor, tree->decls[at]);
  }
}

/* ---- the index ---- */

static int64_t compare_occurrence(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  const Builder *b = (const Builder *)(const void *)env;
  const MsOccurrence *x = (const MsOccurrence *)(const void *)left;
  const MsOccurrence *y = (const MsOccurrence *)(const void *)right;
  const int files = ms_span_compare(module_file(b, x->module), module_file(b, y->module));
  if (files != 0) {
    return files;
  }
  if (x->offset != y->offset) {
    return x->offset < y->offset ? -1 : 1;
  }
  return ms_span_compare(x->key, y->key);
}

static void index_tables(Builder *b) {
  MsCheckProgram *program = b->program;
  const size_t modules = program->user_modules;
  b->symbol_at = MS_ARENA_NEW_ARRAY(b->arena, MsSymbolId *, modules);
  b->method_at = MS_ARENA_NEW_ARRAY(b->arena, const MsMethodEntry **, modules);
  b->param_key = MS_ARENA_NEW_ARRAY(b->arena, MsSpan *, modules);
  b->written = MS_ARENA_NEW_ARRAY(b->arena, MsTy *, modules);
  b->assigned = MS_ARENA_NEW_ARRAY(b->arena, bool *, modules);
  b->folded_into = MS_ARENA_NEW_ARRAY(b->arena, uint32_t *, modules);
  for (size_t module = 0; module < modules; module++) {
    const uint32_t nodes = program->modules.ptr[module].tree->node_count + 1;
    b->symbol_at[module] = MS_ARENA_NEW_ARRAY(b->arena, MsSymbolId, nodes);
    b->method_at[module] = MS_ARENA_NEW_ARRAY(b->arena, const MsMethodEntry *, nodes);
    b->param_key[module] = MS_ARENA_NEW_ARRAY(b->arena, MsSpan, nodes);
    b->written[module] = MS_ARENA_NEW_ARRAY(b->arena, MsTy, nodes);
    b->assigned[module] = MS_ARENA_NEW_ARRAY(b->arena, bool, nodes);
  }
  for (size_t module = 0; module < modules; module++) {
    fold_receivers(b, (uint32_t)module);
  }
  for (size_t index = 1; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->module < modules && symbol->decl != NULL) {
      b->symbol_at[symbol->module][symbol->decl->id] = (MsSymbolId)index;
    }
  }
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->module < modules) {
      b->method_at[entry->module][entry->source->id] = entry;
    }
  }
  for (size_t index = 0; index < program->type_refs.len; index++) {
    const MsTypeRefRecord *record = &program->type_refs.ptr[index];
    if (b->written[record->module][record->node] == MS_TY_NONE) {
      b->written[record->module][record->node] = record->ty; /* the signature pass resolved it first, in scope of its variables */
    }
  }
}

MsOccurrences ms_occurrence_index(MsArena *arena, MsCheckProgram *program) {
  Builder b = {.arena = arena, .program = program};
  index_tables(&b);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    name_parameters(&b, module);
  }
  for (uint32_t module = 0; module < program->user_modules; module++) {
    declare_symbols(&b, module);
  }
  for (uint32_t module = 0; module < program->user_modules; module++) {
    declare_bindings(&b, module);
  }
  declare_methods(&b);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    declare_types(&b, module);
  }
  for (uint32_t module = 0; module < program->user_modules; module++) {
    declare_type_parameters(&b, module);
  }
  for (uint32_t module = 0; module < program->user_modules; module++) {
    declare_uses(&b, module);
  }
  ms_sort((uint8_t *)b.out.ptr, b.out.len, sizeof(MsOccurrence), compare_occurrence, (uint8_t *)&b);
  MsOccurrences unique = {0};
  for (size_t index = 0; index < b.out.len; index++) {
    const MsOccurrence *current = &b.out.ptr[index];
    if (unique.len > 0) {
      const MsOccurrence *last = &unique.ptr[unique.len - 1];
      if (last->module == current->module && last->offset == current->offset && ms_span_equal(last->key, current->key)) {
        continue;
      }
    }
    ms_occurrences_push(arena, &unique, *current);
  }
  return unique;
}

/* ---- type hints ---- */

/* The length in UTF-16 code units of the UTF-8 text `bytes`. */
static size_t utf16_length(const uint8_t *bytes, size_t count) {
  size_t units = 0;
  for (size_t at = 0; at < count; at++) {
    const uint8_t byte = bytes[at];
    if ((byte & 0xC0U) == 0x80U) {
      continue; /* a continuation byte */
    }
    units += byte >= 0xF0U ? 2 : 1;
  }
  return units;
}

MsTypeHints ms_occurrence_type_hints(MsArena *arena, const MsCheckProgram *program, const MsOccurrences *index) {
  MsTypeHints hints = {0};
  uint32_t module = UINT32_MAX;
  size_t line = 0;
  size_t line_start = 0;
  size_t cursor = 0;
  for (size_t at = 0; at < index->len; at++) {
    const MsOccurrence *entry = &index->ptr[at];
    if (entry->ty == MS_TY_NONE || ms_ty_is_invalid(&program->types, entry->ty)) {
      continue;
    }
    const MsSpan source = program->modules.ptr[entry->module].source;
    if (entry->module != module || entry->offset < cursor) {
      module = entry->module;
      line = 0;
      line_start = 0;
      cursor = 0;
    }
    for (; cursor < entry->offset && cursor < source.len; cursor++) {
      if (source.ptr[cursor] == '\n') {
        line++;
        line_start = cursor + 1;
      }
    }
    MsStrBuild text = ms_strbuild_new();
    ms_ty_show(&text, program->names, &program->types, entry->ty);
    const MsSpan ty = ms_arena_copy(arena, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
    ms_type_hints_push(arena, &hints,
                       (MsTypeHint){.file = ms_names_span(program->names, program->modules.ptr[entry->module].file), .ty = ty,
                                    .line = line, .col = utf16_length(source.ptr + line_start, entry->offset - line_start),
                                    .len = utf16_length(source.ptr + entry->offset, entry->end - entry->offset)});
  }
  return hints;
}
