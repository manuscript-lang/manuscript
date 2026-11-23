/* cli/lsp_completion.c: completion. The word under the cursor is replaced by a marker name and the document is checked, so the
 * scope walk shows the bindings in scope at the marker and the checked type of what a member is taken from. */
#include "cli/lsp_completion.h"

#include <stdlib.h>

#include "base/cstr.h"
#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "cli/lsp_workspace.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "compiler/syntax/parse.h"
#include "tooling/facts.h"
#include "compiler/check/scope_walk.h"
#include "tooling/doc_comment.h"

#define MARKER "__manuscript_completion"

typedef struct Item {
  MsString label, detail, documentation, sort, insert;
  int kind, format;
} Item;

MS_LIST_DEFINE(ItemList, item_list, Item)

typedef struct Completer {
  MsSpan source;
  size_t start, end, offset; /* the word under the cursor, and the cursor */
  MsSpan prefix;
  bool member, type_context, snippets;
  LspAnalysis *analysis;
  MsCheckProgram *program;
  uint32_t module; /* the document's module, or UINT32_MAX */
  MsBindingList scope;
  MsNode left; /* the receiver of the member being completed */
  bool has_left;
  ItemList items;
} Completer;

static bool is_word(uint8_t byte) {
  return byte == '_' || (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte >= 0x80;
}

static uint8_t lower(uint8_t byte) { return byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte + 32) : byte; }

/* Case-insensitive subsequence match. */
static bool name_matches(MsSpan name, MsSpan query) {
  size_t at = 0;
  for (size_t i = 0; i < name.len && at < query.len; i++) {
    if (lower(name.ptr[i]) == lower(query.ptr[at])) at++;
  }
  return at == query.len;
}

static bool contains(MsSpan text, const char *needle) {
  size_t at;
  return ms_span_find(text, ms_span_of_text(needle), &at);
}

static MsString own(MsSpan text) { return ms_string_from_span(text); }

static void add(Completer *c, MsSpan name, int kind, MsTy ty, int priority, MsSpan insert, MsSpan documentation) {
  if (!name_matches(name, c->prefix) || ms_span_starts_with(name, ms_span_of_text(MARKER))) return;
  for (size_t i = 0; i < c->items.len; i++) {
    if (ms_span_equal(ms_string_span(&c->items.ptr[i].label), name)) return;
  }
  MsStrBuild sort = ms_strbuild_new();
  ms_strbuild_append_byte(&sort, (uint8_t)('0' + priority / 10));
  ms_strbuild_append_byte(&sort, (uint8_t)('0' + priority % 10));
  ms_strbuild_append_byte(&sort, '_');
  ms_strbuild_append(&sort, name);
  MsStrBuild detail = ms_strbuild_new();
  if (ty != MS_TY_NONE) ms_ty_show(&detail, c->program->names, &c->program->types, ty);
  Item item = {.label = own(name), .detail = ms_strbuild_finish(&detail), .documentation = own(documentation),
               .sort = ms_strbuild_finish(&sort), .insert = own(insert), .kind = kind,
               .format = c->snippets && (contains(insert, "${") || contains(insert, "$0")) ? 2 : 1};
  item_list_push(&c->items, item);
}

static void add_text(Completer *c, const char *name, int kind, MsTy ty, int priority, const char *insert) {
  add(c, ms_span_of_text(name), kind, ty, priority, ms_span_of_text(insert), (MsSpan){0});
}

/* ---- insert text ---- */

/* The text inserted for a callable: with placeholders for the parameters that have no default, when snippets are supported. */
static MsString callable_text(const Completer *c, MsSpan name, MsTy ty, const MsTy *variables, size_t variable_count, const MsParams *ast) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, name);
  const MsTyTable *types = &c->program->types;
  if (!c->snippets || ty == MS_TY_NONE || ms_ty_kind(types, ty) != MS_TY_FUNCTION) return ms_strbuild_finish(&out);
  size_t at = 1;
  if (variable_count > 0) {
    ms_strbuild_append_byte(&out, '[');
    for (size_t i = 0; i < variable_count; i++) {
      if (i > 0) ms_strbuild_append_text(&out, ", ");
      ms_strbuild_printf(&out, "${%zu:", at++);
      ms_strbuild_append(&out, ms_names_span(c->program->names, ms_ty_row(types, variables[i])->name));
      ms_strbuild_append_byte(&out, '}');
    }
    ms_strbuild_append_byte(&out, ']');
  }
  ms_strbuild_append_byte(&out, '(');
  const MsTyParam *params = ms_ty_params(types, ty);
  const size_t count = ms_ty_param_count(types, ty);
  if (ast != NULL && ast->len != count) ast = NULL;
  size_t written = 0;
  for (size_t i = 0; i < count; i++) {
    if (ast != NULL && ast->ptr[i]->def != NULL) continue;
    const MsSpan label = ms_names_span(c->program->names, ast != NULL ? ast->ptr[i]->name : params[i].name);
    if (written > 0) ms_strbuild_append_text(&out, ", ");
    if (count != 1 && label.len > 0) {
      ms_strbuild_append(&out, label);
      ms_strbuild_append_text(&out, ": ");
    }
    ms_strbuild_printf(&out, "${%zu:", at++);
    ms_strbuild_append(&out, label);
    ms_strbuild_append_byte(&out, '}');
    written++;
  }
  ms_strbuild_append_text(&out, ")$0");
  return ms_strbuild_finish(&out);
}

static void add_callable(Completer *c, MsSpan name, int kind, MsTy ty, int priority, const MsTy *variables, size_t variable_count,
                         const MsParams *ast, MsSpan documentation) {
  MsString insert = callable_text(c, name, ty, variables, variable_count, ast);
  add(c, name, kind, ty, priority, ms_string_span(&insert), documentation);
  ms_string_release(&insert);
}

/* ---- documentation ---- */

static MsSpan symbol_documentation(Completer *c, const MsSymbol *symbol) {
  if (symbol->decl == NULL) return (MsSpan){0};
  return ms_declaration_comment(c->analysis->arena, c->program->modules.ptr[symbol->module].source, symbol->decl->pos.offset,
                                symbol->decl->pos.line);
}

/* ---- members ---- */

static void add_case(Completer *c, const MsTyCase *entry, MsTy owner, int priority) {
  const MsSpan name = ms_names_span(c->program->names, entry->name);
  if (entry->fields.len == 0) {
    add(c, name, 20, MS_TY_NONE, priority, name, (MsSpan){0});
    return;
  }
  const MsName fn = ms_names_intern(c->program->names, ms_span_of_text("fn"));
  const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_TY_FUNCTION, .params = entry->fields.ptr,
                         .param_count = (uint32_t)entry->fields.len, .result = owner};
  const MsTy signature = ms_ty_intern(&c->program->types, &desc);
  add_callable(c, name, 20, signature, priority, NULL, 0, NULL, (MsSpan){0});
}

static void add_members(Completer *c, MsTy receiver) {
  MsCheckProgram *program = c->program;
  if (receiver == MS_TY_NONE || ms_ty_is_invalid(&program->types, receiver)) return;
  const uint32_t def_index = ms_ty_row(&program->types, receiver)->def;
  const MsDef *def = def_index == 0 ? NULL : ms_defs_get(&program->defs, def_index);
  if (def != NULL && ms_ty_kind(&program->types, receiver) == MS_TY_TYPE) {
    for (size_t i = 0; i < def->fields.len; i++) {
      add(c, ms_names_span(program->names, def->fields.ptr[i].name), 5, def->fields.ptr[i].ty, 0, ms_names_span(program->names, def->fields.ptr[i].name), (MsSpan){0});
    }
  }
  for (size_t i = 0; def != NULL && i < def->operations.len; i++) {
    const MsOperation *operation = &def->operations.ptr[i];
    add_callable(c, ms_names_span(program->names, operation->name), 2, operation->ty, 0, NULL, 0, NULL, (MsSpan){0});
  }
  for (size_t i = 0; i < program->methods.len; i++) {
    const MsMethodEntry *entry = &program->methods.ptr[i];
    MsTyList bound = {0};
    for (uint32_t at = 0; at < entry->shared; at++) ms_ty_list_push(&bound, MS_TY_NONE);
    const bool applies = ms_check_unify(&program->types, entry->receiver, receiver, entry->variables.ptr, entry->shared, bound.ptr) &&
                         ms_check_bounds_satisfied(program, entry->variables.ptr, entry->shared, bound.ptr);
    MsTyList vars = {0}, args = {0};
    for (uint32_t at = 0; applies && at < entry->shared; at++) {
      if (bound.ptr[at] == MS_TY_NONE) continue;
      ms_ty_list_push(&vars, entry->variables.ptr[at]);
      ms_ty_list_push(&args, bound.ptr[at]);
    }
    const MsTy signature = !applies || vars.len == 0 ? entry->ty : ms_ty_subst(&program->types, entry->ty, vars.ptr, args.ptr, vars.len);
    ms_ty_list_free(&vars);
    ms_ty_list_free(&args);
    ms_ty_list_free(&bound);
    if (!applies) continue;
    add_callable(c, ms_names_span(program->names, entry->name), 2, signature, 0, NULL, 0,
                 entry->source != NULL ? &entry->source->func.params : NULL, (MsSpan){0});
  }
  MsSpanList natives = {0};
  ms_check_native_names(program, receiver, &natives);
  const bool primitive = ms_ty_kind(&program->types, receiver) == MS_TY_PRIMITIVE;
  const bool text = ms_ty_is(&program->types, receiver, MS_BUILTIN_String);
  for (size_t i = 0; i < natives.len; i++) {
    if ((primitive && ms_span_is_text(natives.ptr[i], "clone")) || (text && ms_span_is_text(natives.ptr[i], "to_string"))) continue;
    add(c, natives.ptr[i], 2, MS_TY_NONE, 0, natives.ptr[i], (MsSpan){0});
  }
  ms_span_list_free(&natives);
}

static void member_items(Completer *c) {
  if (!c->has_left || c->module == UINT32_MAX) return;
  const MsFacts *facts = &c->program->modules.ptr[c->module].facts;
  const MsTy ty = ms_facts_type(facts, c->left);
  const MsRef *ref = ms_facts_ref(facts, c->left);
  if (ref != NULL && ref->kind == MS_REF_TYPE) {
    /* A type's own name: the cases of an alternative. */
    if (ty != MS_TY_NONE && ms_ty_kind(&c->program->types, ty) == MS_TY_ALTERNATIVE) {
      const MsDef *def = ms_defs_get(&c->program->defs, ms_ty_row(&c->program->types, ty)->def);
      for (size_t i = 0; i < def->cases.len; i++) add_case(c, &def->cases.ptr[i], ty, 0);
    }
    return;
  }
  add_members(c, ty);
}

/* ---- names in scope ---- */

static MsTy binding_type(const Completer *c, const MsBinding *binding) {
  for (size_t i = 0; i < c->program->bindings.len; i++) {
    const MsLocalRecord *record = &c->program->bindings.ptr[i];
    if (record->module == c->module && record->name == binding->name && record->pos.offset == binding->decl.offset) return record->ty;
  }
  return MS_TY_NONE;
}

static void add_symbol(Completer *c, const MsSymbol *symbol) {
  const MsCheckProgram *program = c->program;
  const MsSpan name = ms_names_span(program->names, symbol->name);
  if (symbol->kind == MS_SYMBOL_ALIAS) {
    if (c->type_context) add(c, name, 7, MS_TY_NONE, 2, name, symbol_documentation(c, symbol));
    return;
  }
  if (c->type_context && symbol->kind != MS_SYMBOL_TYPE) return;
  if (symbol->ty == MS_TY_NONE) return;
  const MsTy *variables = symbol->var_count == 0 ? NULL : program->symbol_vars.ptr + symbol->var_at;
  const MsSpan documentation = symbol_documentation(c, symbol);
  if (symbol->kind == MS_SYMBOL_TYPE) {
    if (c->type_context && c->snippets && symbol->var_count > 0) {
      MsStrBuild insert = ms_strbuild_new();
      ms_strbuild_append(&insert, name);
      ms_strbuild_append_byte(&insert, '[');
      for (uint32_t i = 0; i < symbol->var_count; i++) {
        if (i > 0) ms_strbuild_append_text(&insert, ", ");
        ms_strbuild_printf(&insert, "${%u:", i + 1);
        ms_strbuild_append(&insert, ms_names_span(program->names, ms_ty_row(&program->types, variables[i])->name));
        ms_strbuild_append_byte(&insert, '}');
      }
      ms_strbuild_append_byte(&insert, ']');
      add(c, name, 7, symbol->ty, 2, ms_strbuild_span(&insert), documentation);
      ms_strbuild_free(&insert);
    } else {
      add(c, name, 7, symbol->ty, 2, name, documentation);
    }
    if (!c->type_context && ms_ty_kind(&program->types, symbol->ty) == MS_TY_ALTERNATIVE) {
      const MsDef *def = ms_defs_get(&program->defs, ms_ty_row(&program->types, symbol->ty)->def);
      for (size_t i = 0; i < def->cases.len; i++) add_case(c, &def->cases.ptr[i], symbol->ty, 2);
    }
    return;
  }
  if (symbol->decl != NULL && symbol->decl->kind == MS_D_CONST) {
    add(c, name, 21, symbol->ty, 2, name, documentation);
    return;
  }
  const MsParams *ast = symbol->decl != NULL && symbol->decl->kind == MS_D_FN ? &symbol->decl->u.fn.params : NULL;
  add_callable(c, name, 3, symbol->ty, 2, variables, symbol->var_count, ast, documentation);
}

static void add_scope_symbols(Completer *c, const MsScope *scope, bool prelude_only) {
  size_t cursor = 0;
  MsName key = 0;
  MsSymbolId *id = NULL;
  while (ms_scope_next(scope, &cursor, &key, &id)) {
    if (*id == 0) continue;
    const MsSymbol *symbol = &c->program->symbols.ptr[*id];
    if (prelude_only && !ms_check_is_prelude_symbol(c->program, symbol)) continue;
    add_symbol(c, symbol);
  }
}

static void scope_items(Completer *c) {
  const MsCheckProgram *program = c->program;
  if (!c->type_context) {
    for (size_t i = c->scope.len; i > 0; i--) {
      const MsBinding *binding = &c->scope.ptr[i - 1];
      const MsSpan name = ms_names_span(program->names, binding->name);
      add_callable(c, name, 6, binding_type(c, binding), 0, NULL, 0, NULL, (MsSpan){0});
    }
  }
  if (c->module != UINT32_MAX) {
    add_scope_symbols(c, &program->modules.ptr[c->module].scope, false);
    add_scope_symbols(c, &program->modules.ptr[c->module].imports, false);
  }
  static const char *const PRELUDE_MODULES[] = {"@std/core.ms", "@std/collections/collections.ms"};
  for (size_t m = 0; m < sizeof PRELUDE_MODULES / sizeof PRELUDE_MODULES[0]; m++) {
    const MsName file = ms_names_intern(program->names, ms_span_of_text(PRELUDE_MODULES[m]));
    for (size_t i = 0; i < program->modules.len; i++) {
      if (program->modules.ptr[i].file == file) add_scope_symbols(c, &program->modules.ptr[i].scope, true);
    }
  }
}

/* ---- keywords and type names ---- */

static const char *keyword_template(const char *word) {
  static const char *const TEMPLATES[][2] = {
      {"interface", "interface ${1:Name}:\n    ${0:fn operation() Void}"},
      {"fn", "fn ${1:name}(${2}) ${3:Void}:\n    ${0:return}"},
      {"type", "type ${1:Name}:\n    ${0:field: String}"},
      {"enum", "enum ${1:Name}:\n    ${0:Ready}"},
      {"if", "if ${1:condition}:\n    $0"},
      {"for", "for ${1:item} in ${2:items}:\n    $0"},
      {"test", "test \"${1:name}\":\n    ${0:return}"},
      {"bench", "bench \"${1:name}\":\n    ${0:return}"}};
  for (size_t i = 0; i < sizeof TEMPLATES / sizeof TEMPLATES[0]; i++) {
    if (ms_cstr_equal(TEMPLATES[i][0], word)) return TEMPLATES[i][1];
  }
  return NULL;
}

static void keyword_items(Completer *c) {
  size_t line_start = c->start;
  while (line_start > 0 && c->source.ptr[line_start - 1] != '\n') line_start--;
  bool blank = true;
  for (size_t i = line_start; i < c->start; i++) blank &= c->source.ptr[i] == ' ' || c->source.ptr[i] == '\t' || c->source.ptr[i] == '\r';
  if (blank) {
    static const char *const STATEMENT[] = {"var", "if", "else", "for", "while", "match", "return", "break", "continue"};
    static const char *const TOP[] = {"fn", "type", "enum", "interface", "import", "export", "extern", "test", "bench"};
    const bool top = line_start == c->start;
    const char *const *words = top ? TOP : STATEMENT;
    const size_t count = top ? sizeof TOP / sizeof TOP[0] : sizeof STATEMENT / sizeof STATEMENT[0];
    for (size_t i = 0; i < count; i++) {
      const char *template = c->snippets ? keyword_template(words[i]) : NULL;
      MsStrBuild insert = ms_strbuild_new();
      if (template != NULL) {
        ms_strbuild_append_text(&insert, template);
      } else {
        ms_strbuild_append_text(&insert, words[i]);
        ms_strbuild_append_byte(&insert, ' ');
      }
      add(c, ms_span_of_text(words[i]), 14, MS_TY_NONE, 5, ms_strbuild_span(&insert), (MsSpan){0});
      ms_strbuild_free(&insert);
    }
    if (!top && c->snippets) add_text(c, "if :=", 14, MS_TY_NONE, 5, "if ${1:value} := ${2:optional}:\n    $0");
  }
  if (!c->type_context) {
    static const char *const VALUES[] = {"true", "false", "void", "fn", "not"};
    for (size_t i = 0; i < sizeof VALUES / sizeof VALUES[0]; i++) add_text(c, VALUES[i], 14, MS_TY_NONE, 5, VALUES[i]);
  } else {
    static const char *const TYPES[] = {"Bool", "Int", "Float", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32",
                                        "UInt64", "Float32", "Float64", "String", "Void", "Never", "Equal", "Stringable",
                                        "Comparable", "Hashable", "Clonable", "Optional", "Result", "Error", "List", "Map",
                                        "Set", "ListEntry", "MapEntry"};
    for (size_t i = 0; i < sizeof TYPES / sizeof TYPES[0]; i++) {
      bool shadowed = false;
      for (size_t b = 0; b < c->scope.len; b++) shadowed |= ms_span_is_text(ms_names_span(c->program->names, c->scope.ptr[b].name), TYPES[i]);
      if (!shadowed) add_text(c, TYPES[i], 7, MS_TY_NONE, 3, TYPES[i]);
    }
  }
}

/* ---- the marker walk ---- */

typedef struct Walk {
  Completer *completer;
  MsName marker;
} Walk;

static void walk_name(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  (void)site;
  Walk *walk = context;
  if (expr->kind != MS_E_NAME || expr->u.sym != walk->marker) return;
  walk->completer->scope.len = 0;
  for (size_t i = 0; i < scope->len; i++) ms_binding_list_push(&walk->completer->scope, scope->ptr[i]);
}

static void walk_expr(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  (void)scope;
  (void)site;
  Walk *walk = context;
  if (expr->kind != MS_E_MEMBER || expr->u.member.name != walk->marker) return;
  walk->completer->left = expr->u.member.left->id;
  walk->completer->has_left = true;
}

static int compare_item(const void *left, const void *right) {
  const Item *a = left, *b = right;
  const MsSpan x[2] = {ms_string_span(&a->sort), ms_string_span(&a->detail)};
  const MsSpan y[2] = {ms_string_span(&b->sort), ms_string_span(&b->detail)};
  for (size_t k = 0; k < 2; k++) {
    const size_t common = x[k].len < y[k].len ? x[k].len : y[k].len;
    for (size_t i = 0; i < common; i++) {
      if (x[k].ptr[i] != y[k].ptr[i]) return x[k].ptr[i] < y[k].ptr[i] ? -1 : 1;
    }
    if (x[k].len != y[k].len) return x[k].len < y[k].len ? -1 : 1;
  }
  return 0;
}

/* Whether the cursor is where a type is written: after the `:` of a parameter or field, or after a function header's `)`. */
static bool in_type_position(MsSpan source, size_t start) {
  size_t at = start;
  while (at > 0 && (source.ptr[at - 1] == ' ' || source.ptr[at - 1] == '\t')) at--;
  if (at == 0) return false;
  size_t line_start = at;
  while (line_start > 0 && source.ptr[line_start - 1] != '\n') line_start--;
  const MsSpan line = ms_span_of(source.ptr + line_start, at - line_start);
  LspTokenList tokens = {0};
  lsp_scan_tokens(line, &tokens);
  bool result = false;
  if (tokens.len > 0) {
    const LspEditorToken *last = &tokens.ptr[tokens.len - 1];
    const LspEditorToken *first = &tokens.ptr[0];
    const bool header = first->kind == LSP_TOKEN_NAME &&
                        (ms_span_equal(ms_span_of(line.ptr + first->start, first->end - first->start), ms_span_of_text("fn")) ||
                         ms_span_equal(ms_span_of(line.ptr + first->start, first->end - first->start), ms_span_of_text("export")) ||
                         ms_span_equal(ms_span_of(line.ptr + first->start, first->end - first->start), ms_span_of_text("extern")));
    if (last->kind == LSP_TOKEN_CHAR && line.ptr[last->start] == ':') {
      result = header || (tokens.len == 2 && tokens.ptr[0].kind == LSP_TOKEN_NAME);
    } else if (last->kind == LSP_TOKEN_CHAR && line.ptr[last->start] == ')') {
      result = header;
    }
  }
  lsp_token_list_free(&tokens);
  return result;
}

/* ---- imports ---- */

/* An item with no scoring of its own: sorted by label, the detail naming the module. */
static void import_item(Completer *c, MsSpan label, int kind, MsSpan detail, MsSpan insert) {
  Item item = {.label = own(label), .detail = own(detail), .documentation = own((MsSpan){0}), .sort = own(label), .insert = own(insert),
               .kind = kind, .format = 1};
  item_list_push(&c->items, item);
}

/* The `import` declaration the cursor is in: where it starts and whether it is a parenthesized group. `*braces` is the
 * group depth at the cursor. */
static bool import_site(MsSpan source, size_t word_start, size_t offset, size_t *start, bool *grouped, int *braces) {
  LspTokenList tokens = {0};
  lsp_scan_tokens(ms_span_of(source.ptr, offset), &tokens);
  bool found = false;
  *grouped = false;
  *braces = 0;
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    const MsSpan text = ms_span_of(source.ptr + token->start, token->end - token->start);
    if (token->kind == LSP_TOKEN_NAME && ms_span_is_text(text, "import") && token->end <= word_start) {
      *start = token->start;
      found = true;
      *grouped = false;
      *braces = 0;
    } else if (found && token->kind == LSP_TOKEN_CHAR) {
      if (text.ptr[0] == '(') {
        (*braces)++;
        *grouped = true;
      } else if (text.ptr[0] == ')') {
        (*braces)--;
      } else if (text.ptr[0] == '\n' && *braces <= 0) {
        found = false;
      }
    }
  }
  lsp_token_list_free(&tokens);
  return found;
}

static bool is_type_decl(const MsDecl *decl) {
  return decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM || decl->kind == MS_D_ALIAS || decl->kind == MS_D_INTERFACE;
}

static bool listed(const MsSpanList *names, MsSpan name) {
  for (size_t i = 0; i < names->len; i++) {
    if (ms_span_equal(names->ptr[i], name)) return true;
  }
  return false;
}

/* Offers the exports of the module `text` (named `path`, a bundled module when `bundled`) that match the word and are not
 * imported yet. `known` says the declaration names its module; `with_from` adds ` from "path"` to the inserted name. */
static void add_exports(Completer *c, MsSpan text, MsSpan path, bool bundled, const MsSpanList *imported, bool known, bool with_from) {
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsModule module;
  MsDiag diag;
  if (ms_parse(&arena, &names, text, &module, &diag)) {
    for (uint32_t d = 0; d < module.ndecls; d++) {
      MsName declared;
      const MsDecl *decl = module.decls[d];
      if (!decl->is_exported || !ms_check_declared_name(decl, &declared)) continue;
      const MsSpan name = ms_names_span(&names, declared);
      if ((bundled && ms_check_is_prelude_declaration(path, name)) || listed(imported, name) || !name_matches(name, c->prefix)) continue;
      MsStrBuild insert = ms_strbuild_new();
      ms_strbuild_append(&insert, name);
      if (with_from) {
        ms_strbuild_append_text(&insert, " from \"");
        ms_strbuild_append(&insert, path);
        ms_strbuild_append_byte(&insert, '"');
      }
      import_item(c, name, !known ? 7 : (is_type_decl(decl) ? 7 : decl->kind == MS_D_CONST ? 21 : 3), path, ms_strbuild_span(&insert));
      ms_strbuild_free(&insert);
    }
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
}

/* The bundled modules a user may import: not the internal ones, and not the two that hold only prelude names. */
static bool public_module(MsSpan name) { return !ms_span_starts_with(name, ms_span_of_text("internal/")); }

static bool has_public_export(MsSpan name, MsSpan text) {
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsModule module;
  MsDiag diag;
  bool found = false;
  if (ms_parse(&arena, &names, text, &module, &diag)) {
    MsStrBuild file = ms_strbuild_new();
    ms_strbuild_append_text(&file, "@std/");
    ms_strbuild_append(&file, name);
    for (uint32_t d = 0; d < module.ndecls && !found; d++) {
      MsName declared;
      const MsDecl *decl = module.decls[d];
      found = decl->is_exported && ms_check_declared_name(decl, &declared) &&
              !ms_check_is_prelude_declaration(ms_strbuild_span(&file), ms_names_span(&names, declared));
    }
    ms_strbuild_free(&file);
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
  return found;
}

static void add_path(Completer *c, MsSpan path, bool directory) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, path);
  if (directory) ms_strbuild_append_byte(&text, '/');
  import_item(c, ms_strbuild_span(&text), 17, ms_strbuild_span(&text), ms_strbuild_span(&text));
  ms_strbuild_free(&text);
}

static int compare_entry(const void *left, const void *right) {
  return (int)ms_span_compare(ms_string_span(&((const MsDirEntry *)left)->name), ms_string_span(&((const MsDirEntry *)right)->name));
}

/* The module paths that start with `prefix`: bundled modules and, after `./` or `../`, the entries of that directory. */
static void path_items(Completer *c, const LspDoc *doc, MsSpan prefix) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  MsStrBuild path = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    if (!public_module(sources[i].name) || !has_public_export(sources[i].name, sources[i].text)) continue;
    ms_strbuild_clear(&path);
    ms_strbuild_append_text(&path, "@std/");
    ms_strbuild_append(&path, sources[i].name);
    if (ms_span_starts_with(ms_strbuild_span(&path), prefix)) add_path(c, ms_strbuild_span(&path), false);
  }
  ms_strbuild_free(&path);
  const bool relative = ms_span_starts_with(prefix, ms_span_of_text("./")) || ms_span_starts_with(prefix, ms_span_of_text("../"));
  size_t slash = prefix.len;
  while (slash > 0 && prefix.ptr[slash - 1] != '/') slash--;
  if (!relative || slash == 0) return;
  const MsSpan directory_prefix = ms_span_of(prefix.ptr, slash);
  MsArena arena = ms_arena_new();
  MsStrBuild base = ms_strbuild_new(), joined = ms_strbuild_new(), cleaned = ms_strbuild_new(), inside = ms_strbuild_new();
  ms_path_dir(ms_string_span(&doc->path), &base);
  ms_path_join(ms_strbuild_span(&base), directory_prefix, &joined);
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  const MsSpan root = lsp_project_root(&arena, ms_strbuild_span(&base));
  MsDirEntryList entries = {0};
  if (ms_path_relative(&inside, root, ms_strbuild_span(&cleaned)) && !ms_path_escapes(ms_strbuild_span(&inside)) &&
      ms_dir_list(ms_strbuild_span(&cleaned), &entries)) {
    if (entries.len > 1) qsort(entries.ptr, entries.len, sizeof(MsDirEntry), compare_entry);
    for (size_t i = 0; i < entries.len; i++) {
      const MsSpan name = ms_string_span(&entries.ptr[i].name);
      const MsSpan full = ms_message_format(&arena, "%S%S", directory_prefix, name);
      MsStrBuild entry_path = ms_strbuild_new();
      ms_path_join(ms_strbuild_span(&cleaned), name, &entry_path);
      const bool directory = entries.ptr[i].kind == MS_PATH_DIRECTORY ||
                             (entries.ptr[i].kind == MS_PATH_SYMLINK && ms_dir_exists(ms_strbuild_span(&entry_path)));
      ms_strbuild_free(&entry_path);
      if (ms_span_starts_with(full, prefix) && (directory || ms_span_ends_with(name, ms_span_of_text(".ms")))) add_path(c, full, directory);
    }
  }
  ms_dir_entries_free(&entries);
  ms_strbuild_free(&base);
  ms_strbuild_free(&joined);
  ms_strbuild_free(&cleaned);
  ms_strbuild_free(&inside);
  ms_arena_free(&arena);
}

/* The module path of the `from "..."` that follows the cursor in the same declaration. */
static bool following_path(MsSpan source, size_t from, int braces, MsSpan *path) {
  const int depth = braces; /* a group's entry names its module at the group's depth */
  LspTokenList tokens = {0};
  lsp_scan_tokens(ms_span_of(source.ptr + from, source.len - from), &tokens);
  bool found = false;
  for (size_t i = 0; i < tokens.len && !found; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    const MsSpan text = ms_span_of(source.ptr + from + token->start, token->end - token->start);
    if ((token->kind == LSP_TOKEN_CHAR && text.ptr[0] == '\n' && braces <= 0) || (token->kind == LSP_TOKEN_NAME && ms_span_is_text(text, "import"))) break;
    if (token->kind == LSP_TOKEN_CHAR && text.ptr[0] == '(') braces++;
    if (token->kind == LSP_TOKEN_CHAR && text.ptr[0] == ')') braces--;
    if (braces < depth) break;
    if (braces == depth && token->kind == LSP_TOKEN_NAME && ms_span_is_text(text, "from") && i + 1 < tokens.len &&
        tokens.ptr[i + 1].kind == LSP_TOKEN_STRING) {
      const LspEditorToken *quoted = &tokens.ptr[i + 1];
      const MsSpan literal = ms_span_of(source.ptr + from + quoted->start, quoted->end - quoted->start);
      if (literal.len >= 2 && literal.ptr[literal.len - 1] == '"' && literal.ptr[0] == '"') {
        *path = ms_span_of(literal.ptr + 1, literal.len - 2);
        found = true;
      }
    }
  }
  lsp_token_list_free(&tokens);
  return found;
}

/* The names an import declaration already lists, except the word under the cursor. */
static void imported_names(Completer *c, size_t start, bool grouped, MsSpanList *out) {
  size_t stop = start;
  while (stop < c->source.len && c->source.ptr[stop] != (grouped ? ')' : '\n')) stop++;
  LspTokenList tokens = {0};
  lsp_scan_tokens(ms_span_of(c->source.ptr + start, stop - start), &tokens);
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    const MsSpan text = ms_span_of(c->source.ptr + start + token->start, token->end - token->start);
    if (token->kind != LSP_TOKEN_NAME || ms_span_is_text(text, "import") || ms_span_is_text(text, "from")) continue;
    if (start + token->end <= c->start || start + token->start >= c->end) ms_span_list_push(out, text);
  }
  lsp_token_list_free(&tokens);
}

/* Completion inside an `import` declaration: module paths in the string, exported names elsewhere. False outside one. */
static bool import_items(Completer *c, const LspDoc *doc, const LspDocList *docs) {
  size_t start;
  bool grouped;
  int braces;
  if (!import_site(c->source, c->start, c->offset, &start, &grouped, &braces)) return false;
  LspTokenList tokens = {0};
  lsp_scan_tokens(ms_span_of(c->source.ptr + start, c->offset - start), &tokens);
  size_t quote = SIZE_MAX;
  for (size_t i = 0; i < tokens.len && quote == SIZE_MAX; i++) {
    if (tokens.ptr[i].kind == LSP_TOKEN_STRING) quote = start + tokens.ptr[i].start;
  }
  lsp_token_list_free(&tokens);
  if (quote != SIZE_MAX) {
    c->start = quote + 1;
    c->end = c->offset;
    while (c->end < c->source.len && c->source.ptr[c->end] != '"' && c->source.ptr[c->end] != '\n') c->end++;
    path_items(c, doc, ms_span_of(c->source.ptr + c->start, c->offset - c->start));
    qsort(c->items.ptr, c->items.len, sizeof(Item), compare_item);
    return true;
  }
  MsSpanList imported = {0};
  imported_names(c, start, grouped, &imported);
  MsSpan path;
  if (following_path(c->source, c->end, braces, &path)) {
    if (ms_span_starts_with(path, ms_span_of_text("@std/"))) {
      MsStdSource source;
      if (ms_std_source_find(ms_span_of(path.ptr + 5, path.len - 5), &source)) add_exports(c, source.text, path, true, &imported, true, false);
    } else if (ms_span_starts_with(path, ms_span_of_text("."))) {
      MsStrBuild base = ms_strbuild_new(), joined = ms_strbuild_new(), file = ms_strbuild_new();
      ms_path_dir(ms_string_span(&doc->path), &base);
      ms_path_join(ms_strbuild_span(&base), path, &joined);
      ms_path_clean(&file, ms_strbuild_span(&joined));
      MsBytes bytes = {0};
      MsSpan text = {0};
      for (size_t i = 0; i < docs->len; i++) {
        if (ms_span_equal(ms_string_span(&docs->ptr[i].path), ms_strbuild_span(&file))) text = ms_string_span(&docs->ptr[i].text);
      }
      const bool on_disk = text.ptr == NULL && ms_file_read(ms_strbuild_span(&file), &bytes);
      if (on_disk) text = ms_bytes_span(&bytes);
      if (text.ptr != NULL) add_exports(c, text, path, false, &imported, true, false);
      if (on_disk) ms_bytes_free(&bytes);
      ms_strbuild_free(&base);
      ms_strbuild_free(&joined);
      ms_strbuild_free(&file);
    }
  } else {
    size_t count = 0;
    const MsStdSource *sources = ms_std_sources(&count);
    MsStrBuild module = ms_strbuild_new();
    for (size_t i = 0; i < count; i++) {
      if (!public_module(sources[i].name)) continue;
      ms_strbuild_clear(&module);
      ms_strbuild_append_text(&module, "@std/");
      ms_strbuild_append(&module, sources[i].name);
      add_exports(c, sources[i].text, ms_strbuild_span(&module), true, &imported, false, !grouped);
    }
    ms_strbuild_free(&module);
  }
  ms_span_list_free(&imported);
  if (c->items.len > 1) qsort(c->items.ptr, c->items.len, sizeof(Item), compare_item);
  return true;
}

/* The marked document's analysis and, from it, the items of the cursor's place. */
static void checked_items(Completer *c, const LspDocList *docs, const LspDoc *doc, MsStrBuild *marked, LspAnalysis *analysis) {
  const MsSpan source = c->source;
  /* The document with the word replaced by the marker. */
  ms_strbuild_append(marked, ms_span_of(source.ptr, c->start));
  ms_strbuild_append_text(marked, MARKER);
  /* A bare name is no statement, so the marker is written as a call: the checker then still reaches what follows it. */
  if (!c->type_context && !(c->end < source.len && source.ptr[c->end] == '(')) ms_strbuild_append_text(marked, "()");
  ms_strbuild_append(marked, ms_span_of(source.ptr + c->end, source.len - c->end));
  const MsOverlayFile changed = {ms_string_span(&doc->path), ms_strbuild_span(marked)};
  lsp_analyze_changed(docs, doc, &changed, 1, analysis);
  c->analysis = analysis;
  c->program = &analysis->checked.program;
  if (analysis->resolved) {
    for (uint32_t m = 0; m < c->program->user_modules; m++) {
      if (ms_span_equal(analysis->paths[m], ms_string_span(&doc->path))) c->module = m;
    }
  }
  if (c->module != UINT32_MAX) {
    Walk walk = {c, ms_names_intern(c->program->names, ms_span_of_text(MARKER))};
    const MsScopeVisitor visitor = {.context = &walk, .name = walk_name, .expr = walk_expr};
    ms_scope_walk_module(c->program->modules.ptr[c->module].tree, &visitor, c->program->names);
  }
  if (analysis->resolved) {
    if (c->member) {
      member_items(c);
    } else {
      scope_items(c);
      keyword_items(c);
    }
  }
}

void lsp_completion(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool snippets, MsStrBuild *out) {
  const MsSpan source = ms_string_span(&doc->text);
  size_t offset;
  if (!lsp_offset(source, position, false, &offset)) {
    ms_strbuild_append_text(out, "[]");
    return;
  }
  LspTokenList tokens = {0};
  lsp_scan_tokens(source, &tokens);
  bool in_string = false;
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    const bool inside = offset > token->start && offset <= token->end && (token->kind != LSP_TOKEN_STRING || offset < token->end);
    if (inside && token->kind == LSP_TOKEN_COMMENT) {
      lsp_token_list_free(&tokens);
      ms_strbuild_append_text(out, "[]");
      return;
    }
    in_string |= inside && token->kind == LSP_TOKEN_STRING;
  }
  lsp_token_list_free(&tokens);
  Completer c = {.source = source, .snippets = snippets, .offset = offset, .module = UINT32_MAX};
  c.start = offset;
  while (c.start > 0 && is_word(source.ptr[c.start - 1])) c.start--;
  c.end = offset;
  while (c.end < source.len && is_word(source.ptr[c.end])) c.end++;
  c.prefix = ms_span_of(source.ptr + c.start, offset - c.start);
  c.member = c.start > 0 && source.ptr[c.start - 1] == '.';
  c.type_context = !c.member && in_type_position(source, c.start);
  if (c.end < source.len && source.ptr[c.end] == '(') c.snippets = false; /* the call is already written */
  LspAnalysis analysis = {0};
  MsStrBuild marked = ms_strbuild_new();
  const bool imports = (in_string || !c.member) && import_items(&c, doc, docs);
  if (in_string && !imports) {
    item_list_free(&c.items);
    ms_strbuild_free(&marked);
    ms_strbuild_append_text(out, "[]");
    return;
  }
  if (!imports) checked_items(&c, docs, doc, &marked, &analysis);
  if (!imports && c.items.len > 1) qsort(c.items.ptr, c.items.len, sizeof(Item), compare_item);
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < c.items.len; i++) {
    const Item *item = &c.items.ptr[i];
    if (i > 0) ms_strbuild_append_byte(out, ',');
    ms_strbuild_append_text(out, "{\"label\":");
    lsp_json_string(out, ms_string_span(&item->label));
    ms_strbuild_printf(out, ",\"kind\":%d,\"sortText\":", item->kind);
    lsp_json_string(out, ms_string_span(&item->sort));
    ms_strbuild_append_text(out, ",\"filterText\":");
    lsp_json_string(out, ms_string_span(&item->label));
    ms_strbuild_printf(out, ",\"insertTextFormat\":%d,\"textEdit\":{\"range\":", item->format);
    ms_strbuild_printf(out, "{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}",
                       lsp_position(source, c.start).line, lsp_position(source, c.start).character, lsp_position(source, c.end).line,
                       lsp_position(source, c.end).character);
    ms_strbuild_append_text(out, ",\"newText\":");
    lsp_json_string(out, ms_string_span(&item->insert));
    ms_strbuild_append_byte(out, '}');
    if (ms_string_length(&item->detail) > 0) {
      ms_strbuild_append_text(out, ",\"detail\":");
      lsp_json_string(out, ms_string_span(&item->detail));
    }
    if (ms_string_length(&item->documentation) > 0) {
      ms_strbuild_append_text(out, ",\"documentation\":{\"kind\":\"markdown\",\"value\":");
      lsp_json_string(out, ms_string_span(&item->documentation));
      ms_strbuild_append_byte(out, '}');
    }
    ms_strbuild_append_byte(out, '}');
  }
  ms_strbuild_append_byte(out, ']');
  for (size_t i = 0; i < c.items.len; i++) {
    ms_string_release(&c.items.ptr[i].label);
    ms_string_release(&c.items.ptr[i].detail);
    ms_string_release(&c.items.ptr[i].documentation);
    ms_string_release(&c.items.ptr[i].sort);
    ms_string_release(&c.items.ptr[i].insert);
  }
  item_list_free(&c.items);
  ms_binding_list_free(&c.scope);
  if (!imports) lsp_analysis_release(&analysis);
  ms_strbuild_free(&marked);
}
