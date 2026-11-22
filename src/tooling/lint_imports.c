/* Owns the unused-import rule of lint.h: MSL102, with the edit that removes the import. Port of the import half of
 * crates/ms-tooling/src/lint/bindings.rs. */
#include "compiler/syntax/lex.h"
#include "compiler/syntax/walk.h"
#include "tooling/lint.h"

/* Names a module writes as types, as a plain list: a module names few. */
MS_LIST_DEFINE(NameSet, name_set, MsName)

static void name_add(NameSet *set, MsName name) {
  for (size_t i = 0; i < set->len; i++) {
    if (set->ptr[i] == name) {
      return;
    }
  }
  name_set_push(set, name);
}

static bool name_has(const NameSet *set, MsName name) {
  for (size_t i = 0; i < set->len; i++) {
    if (set->ptr[i] == name) {
      return true;
    }
  }
  return false;
}

/* What one module's scan found: the types it writes, and which literals need a canonical import. */
typedef struct Scan {
  MsNames *names;
  NameSet types;
  bool list, map, decimal;
} Scan;

/* The first segment of a possibly dotted type name. */
static MsName head_name(const Scan *scan, MsName name) {
  const MsSpan text = ms_names_span(scan->names, name);
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '.') {
      return ms_names_intern(scan->names, ms_span_of(text.ptr, i));
    }
  }
  return name;
}

static void scan_type(Scan *scan, const MsTypeRef *type);

static void scan_params(Scan *scan, MsParams params) {
  for (uint32_t i = 0; i < params.len; i++) {
    scan_type(scan, params.ptr[i]->ty); /* a default is an expression: the walker reaches it */
  }
}

static void scan_type(Scan *scan, const MsTypeRef *type) {
  if (type == NULL) {
    return;
  }
  if (type->kind == MS_TYPE_NAMED) {
    name_add(&scan->types, head_name(scan, type->name));
    for (uint32_t i = 0; i < type->args.len; i++) {
      scan_type(scan, type->args.ptr[i]);
    }
    return;
  }
  scan_params(scan, type->params);
  scan_type(scan, type->result);
}

static void scan_type_list(Scan *scan, MsTypeRefs types) {
  for (uint32_t i = 0; i < types.len; i++) {
    scan_type(scan, types.ptr[i]);
  }
}

static void scan_type_params(Scan *scan, MsTypeParams params) {
  for (uint32_t i = 0; i < params.len; i++) {
    scan_type_list(scan, params.ptr[i]->bounds);
    scan_type(scan, params.ptr[i]->def);
  }
}

static void scan_func(Scan *scan, const MsFunc *func) {
  scan_type_params(scan, func->type_params);
  scan_params(scan, func->params);
  scan_type(scan, func->result);
}

static void scan_decl_types(Scan *scan, const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    scan_func(scan, &decl->u.fn);
    break;
  case MS_D_CONST:
    scan_type(scan, decl->u.konst.ty);
    break;
  case MS_D_TYPE:
    scan_type_params(scan, decl->u.type.type_params);
    scan_params(scan, decl->u.type.fields);
    break;
  case MS_D_ENUM:
    scan_type_params(scan, decl->u.enumeration.type_params);
    for (uint32_t i = 0; i < decl->u.enumeration.cases.len; i++) {
      scan_params(scan, decl->u.enumeration.cases.ptr[i]->fields);
    }
    break;
  case MS_D_ALIAS:
    scan_type_params(scan, decl->u.alias.type_params);
    scan_type_list(scan, decl->u.alias.targets);
    break;
  case MS_D_INTERFACE:
    scan_type_params(scan, decl->u.iface.type_params);
    for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
      scan_func(scan, &decl->u.iface.methods.ptr[i]->func);
      scan_type_list(scan, decl->u.iface.methods.ptr[i]->receiver_args);
    }
    break;
  case MS_D_IMPL:
    scan_type(scan, decl->u.impl.contract);
    scan_type(scan, decl->u.impl.receiver);
    scan_type_params(scan, decl->u.impl.bounds);
    for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
      scan_func(scan, &decl->u.impl.methods.ptr[i]->func);
      scan_type_list(scan, decl->u.impl.methods.ptr[i]->receiver_args);
    }
    break;
  case MS_D_TEST:
    break;
  }
}

static bool is_decimal_literal(MsSpan text) {
  const bool based = text.len > 1 && text.ptr[0] == '0' && (text.ptr[1] == 'x' || text.ptr[1] == 'b');
  return !based && text.len > 0 && text.ptr[text.len - 1] == 'd';
}

static void scan_stmt(void *ctx, const MsStmt *stmt) {
  Scan *scan = ctx;
  if (stmt->kind == MS_S_BIND) {
    scan_type(scan, stmt->u.bind.ty);
  }
}

static void scan_expr(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  switch ((MsExprKind)expr->kind) {
  case MS_E_LIST:
    scan->list = true;
    break;
  case MS_E_MAP:
    scan->map = true;
    break;
  case MS_E_NUMBER:
    scan->decimal = scan->decimal || is_decimal_literal(ms_names_span(scan->names, expr->u.sym));
    break;
  case MS_E_APPLY:
    scan_type_list(scan, expr->u.apply.types);
    break;
  case MS_E_LAMBDA:
    scan_params(scan, expr->u.lambda.params);
    scan_type(scan, expr->u.lambda.result);
    break;
  default:
    break;
  }
}

static void scan_module(Scan *scan, const MsModule *tree) {
  const MsVisitor visitor = {.ctx = scan, .stmt = scan_stmt, .expr = scan_expr};
  for (uint32_t i = 0; i < tree->ndecls; i++) {
    scan_decl_types(scan, tree->decls[i]);
    ms_walk_decl(&visitor, tree->decls[i]);
  }
}

/* Whether any use of the module resolves to the declaration of `symbol`. */
static bool referenced(const MsFacts *facts, const MsSymbol *symbol) {
  if (symbol->decl == NULL) {
    return true; /* nothing to compare with: do not claim it unused */
  }
  for (uint32_t node = 0; node < facts->node_count; node++) {
    const MsRef *ref = &facts->refs[node];
    const bool symbol_kind = ref->kind == MS_REF_FUNCTION || ref->kind == MS_REF_TYPE ||
                             ref->kind == MS_REF_CONSTANT || ref->kind == MS_REF_NATIVE;
    if (symbol_kind && ref->decl.module == symbol->module && ref->decl.node == symbol->decl->id) {
      return true;
    }
  }
  return false;
}

static MsPos pos_at(MsSpan source, size_t offset) {
  uint32_t line = 1;
  size_t line_start = 0;
  for (size_t i = 0; i < offset && i < source.len; i++) {
    if (source.ptr[i] == '\n') {
      line++;
      line_start = i + 1;
    }
  }
  return (MsPos){(uint32_t)offset, line, (uint32_t)(offset - line_start + 1)};
}

static bool is_blank(uint8_t c) {
  return c == ' ' || c == '\t';
}

static bool is_space(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

static size_t skip_blank(MsSpan source, size_t at) {
  while (at < source.len && is_blank(source.ptr[at])) {
    at++;
  }
  return at;
}

static size_t line_start_of(MsSpan source, size_t at) {
  while (at > 0 && source.ptr[at - 1] != '\n') {
    at--;
  }
  return at;
}

static bool all_space(MsSpan source, size_t from, size_t to) {
  for (size_t i = from; i < to; i++) {
    if (!is_space(source.ptr[i])) {
      return false;
    }
  }
  return true;
}

/* The tokens of the statement an import starts, from its `import` keyword on. */
typedef struct Statement {
  const MsToken *ptr;
  size_t len;
} Statement;

static Statement statement_of(const MsLexed *lexed, uint32_t offset) {
  size_t low = 0;
  size_t high = lexed->ntokens;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    if (lexed->tokens[middle].pos.offset < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return (Statement){lexed->tokens + low, lexed->ntokens - low};
}

static bool in_group(MsSpan source, Statement rest) {
  if (rest.len < 2 || rest.ptr[1].kind != MS_T_LParen) {
    return false;
  }
  for (size_t i = 2; i < rest.len && rest.ptr[i].kind != MS_T_RParen; i++) {
    const MsToken *token = &rest.ptr[i];
    if (token->kind == MS_T_Name &&
        ms_span_is_text(ms_span_of(source.ptr + token->pos.offset, token->end.offset - token->pos.offset), "from")) {
      return true;
    }
  }
  return false;
}

/* The byte range that deletes this binding's clause from a grouped import, or the whole statement. */
static bool group_removal(MsSpan source, const MsImport *import, Statement rest, bool statement, size_t *from,
                          size_t *to) {
  const size_t start = statement ? import->pos.offset : import->clause.offset;
  size_t end = 0;
  if (statement) {
    size_t depth = 0;
    bool closed = false;
    for (size_t i = 1; i < rest.len && !closed; i++) {
      if (rest.ptr[i].kind == MS_T_LParen) {
        depth++;
      } else if (rest.ptr[i].kind == MS_T_RParen) {
        if (depth == 0) {
          return false;
        }
        depth--;
        if (depth == 0) {
          end = rest.ptr[i].end.offset;
          closed = true;
        }
      }
    }
    if (!closed) {
      return false;
    }
  } else {
    size_t first = 0;
    while (first < rest.len && rest.ptr[first].pos.offset < import->clause.offset) {
      first++;
    }
    while (first < rest.len && rest.ptr[first].kind != MS_T_String) {
      first++;
    }
    if (first == rest.len) {
      return false;
    }
    end = skip_blank(source, rest.ptr[first].end.offset);
    if (end < source.len && source.ptr[end] == ',') {
      end++;
    }
  }
  const size_t line_start = line_start_of(source, start);
  size_t line_end = end;
  while (line_end < source.len && source.ptr[line_end] != '\n') {
    line_end++;
  }
  if (all_space(source, line_start, start) && all_space(source, end, line_end)) {
    *from = line_start;
    *to = line_end + (line_end < source.len ? 1 : 0);
    return true;
  }
  *from = start;
  *to = end;
  return true;
}

/* Deletes the whole `import ... from "path"` statement, with its line breaks. */
static bool statement_removal(MsSpan source, const MsImport *import, Statement rest, size_t *from, size_t *to) {
  const size_t start = import->pos.offset;
  size_t path = 0;
  while (path < rest.len && rest.ptr[path].kind != MS_T_String) {
    path++;
  }
  if (path == rest.len) {
    return false;
  }
  const size_t close = rest.ptr[path].end.offset;
  size_t line_end = close;
  while (line_end < source.len && source.ptr[line_end] != '\n') {
    line_end++;
  }
  line_end += line_end < source.len ? 1 : 0;
  const size_t line_start = line_start_of(source, start);
  *from = all_space(source, line_start, start) ? line_start : start;
  *to = line_end;
  return true;
}

/* Deletes one name and its separator from an import list that keeps other names. */
static bool name_removal(MsSpan source, const MsImport *import, size_t name_length, size_t *from, size_t *to) {
  const size_t start = import->name_pos.offset;
  const size_t end = start + name_length;
  const size_t after = skip_blank(source, end);
  if (after < source.len && source.ptr[after] == ',') {
    const size_t next = skip_blank(source, after + 1);
    const size_t line_start = line_start_of(source, start);
    size_t newline = 0;
    if (next + 1 < source.len && source.ptr[next] == '\r' && source.ptr[next + 1] == '\n') {
      newline = 2;
    } else if (next < source.len && source.ptr[next] == '\n') {
      newline = 1;
    }
    if (newline > 0 && all_space(source, line_start, start)) {
      *from = line_start;
      *to = next + newline;
    } else {
      *from = start;
      *to = next;
    }
    return true;
  }
  size_t before = start;
  while (before > 0 && is_blank(source.ptr[before - 1])) {
    before--;
  }
  if (before == 0 || source.ptr[before - 1] != ',') {
    return false;
  }
  *from = before - 1;
  *to = end;
  return true;
}

static bool same_pos(MsPos a, MsPos b) {
  return a.offset == b.offset && a.line == b.line && a.column == b.column;
}

void ms_lint_imports(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                     MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  const MsModule *tree = module->tree;
  if (tree == NULL || tree->nimports == 0) {
    return;
  }
  Scan scan = {.names = program->names};
  scan_module(&scan, tree);
  bool *unused = MS_ARENA_NEW_ARRAY(arena, bool, tree->nimports);
  for (uint32_t i = 0; i < tree->nimports; i++) {
    const MsImport *import = &tree->imports[i];
    const MsSymbolId *id = ms_scope_get(&module->imports, import->name);
    const MsSymbol *symbol = id != NULL && *id != 0 ? &program->symbols.ptr[*id] : NULL;
    const MsSpan name = ms_names_span(program->names, import->name);
    bool used = symbol != NULL && referenced(&module->facts, symbol);
    used = used || (symbol != NULL && name_has(&scan.types, import->name));
    used = used || (symbol != NULL && ((scan.list && ms_span_is_text(name, "List")) ||
                                       (scan.map && ms_span_is_text(name, "Map")) ||
                                       (scan.decimal && ms_span_is_text(name, "Decimal"))));
    unused[i] = !used;
  }
  name_set_free(&scan.types);
  const MsSpan file = ms_names_span(program->names, module->file);
  MsLexed lexed = {0};
  MsDiag diag = {0};
  const bool lexable = ms_lex(arena, module->source, &lexed, &diag);
  for (uint32_t i = 0; i < tree->nimports; i++) {
    if (!unused[i]) {
      continue;
    }
    const MsImport *import = &tree->imports[i];
    const MsSpan name = ms_names_span(program->names, import->name);
    bool whole = true;
    bool statement_unused = true;
    for (uint32_t k = 0; k < tree->nimports; k++) {
      const MsImport *sibling = &tree->imports[k];
      whole = whole && (!same_pos(sibling->clause, import->clause) || unused[k]);
      statement_unused = statement_unused && (!same_pos(sibling->pos, import->pos) || unused[k]);
    }
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "Import ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, " is never used");
    MsLintFinding *found = ms_lint_add(findings, "MSL102", file, import->name_pos,
                                       ms_arena_copy(arena, ms_strbuild_span(&text)));
    ms_strbuild_free(&text);
    const Statement rest = lexable ? statement_of(&lexed, import->pos.offset) : (Statement){0};
    const bool grouped = whole && lexable && in_group(module->source, rest);
    size_t from = 0;
    size_t to = 0;
    bool fixed = false;
    if (grouped) {
      fixed = group_removal(module->source, import, rest, statement_unused, &from, &to);
    } else if (whole) {
      fixed = lexable && statement_removal(module->source, import, rest, &from, &to);
    } else {
      fixed = name_removal(module->source, import, name.len, &from, &to);
    }
    if (fixed) {
      found->has_fix = true;
      found->fix_pos = pos_at(module->source, from);
      found->fix_end = pos_at(module->source, to);
      found->replacement = (MsSpan){0};
    }
  }
}
