/* cli/lsp_completion_imports.c: completion that concerns imports: module paths and exported names inside an `import`
 * declaration, and names not imported yet, offered with the import that makes them visible. */
#include <stdlib.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "cli/lsp_actions.h"
#include "cli/lsp_completion_internal.h"
#include "cli/lsp_workspace.h"
#include "compiler/project/manifest.h"
#include "compiler/project/project.h"
#include "compiler/syntax/parse.h"
#include "tooling/doc_comment.h"
#include "tooling/facts.h"

/* ---- names that are not imported yet ---- */

static bool is_type_decl(const MsDecl *decl);
static bool public_module(MsSpan name);

/* The placeholders of a function's parameters that have no default, or the bare name without snippets. */
static MsString declared_call_text(bool snippets, const MsNames *names, MsSpan name, const MsParams *params) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, name);
  if (!snippets) return ms_strbuild_finish(&out);
  ms_strbuild_append_byte(&out, '(');
  size_t at = 1, written = 0;
  for (uint32_t i = 0; i < params->len; i++) {
    if (params->ptr[i]->def != NULL) continue;
    const MsSpan label = ms_names_span(names, params->ptr[i]->name);
    if (written > 0) ms_strbuild_append_text(&out, ", ");
    if (params->len != 1) {
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

/* One exported name of a module, with everything an offer needs, so a module is parsed once and not per keystroke. */
typedef struct Importable {
  MsString name, path, documentation, plain, call; /* `call` is the snippet form; `plain` the bare name */
  int kind;
  bool is_type;
} Importable;

MS_LIST_DEFINE(ImportableList, importable_list, Importable)

static void importable_list_release(ImportableList *list) {
  for (size_t i = 0; i < list->len; i++) {
    Importable *item = &list->ptr[i];
    ms_string_release(&item->name);
    ms_string_release(&item->path);
    ms_string_release(&item->documentation);
    ms_string_release(&item->plain);
    ms_string_release(&item->call);
  }
  importable_list_free(list);
}

/* Parses the module `text` (imported as `path`) and appends its exported names to `out`. */
static void collect_importable(MsSpan text, MsSpan path, bool bundled, ImportableList *out) {
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
      if (ms_span_starts_with(name, ms_span_of_text(MARKER))) continue;
      if (bundled && ms_check_is_prelude_declaration(path, name)) continue;
      const bool is_type = is_type_decl(decl);
      const bool function = decl->kind == MS_D_FN;
      const MsSpan comment = ms_declaration_comment(&arena, text, decl->pos.offset, decl->pos.line);
      importable_list_push(out, (Importable){.name = own(name),
                                             .path = own(path),
                                             .documentation = own(comment),
                                             .plain = own(name),
                                             .call = function ? declared_call_text(true, &names, name, &decl->u.fn.params) : own(name),
                                             .kind = is_type ? 7 : decl->kind == MS_D_CONST ? 21 : 3,
                                             .is_type = is_type});
    }
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
}

/* Offers `item` when it matches the word, with the edit that imports it. */
static void offer_importable(Completer *c, const Importable *item) {
  const MsSpan name = ms_string_span(&item->name), path = ms_string_span(&item->path);
  if (!name_matches(name, c->prefix)) return;
  if (c->type_context && !item->is_type) return;
  for (size_t i = 0; i < c->items.len; i++) {
    if (ms_span_equal(ms_string_span(&c->items.ptr[i].label), name)) return;
  }
  MsString insert = own(ms_string_span(c->snippets ? &item->call : &item->plain));
  MsStrBuild detail = ms_strbuild_new();
  ms_strbuild_append_text(&detail, "— ");
  ms_strbuild_append(&detail, path);
  MsStrBuild statement = ms_strbuild_new();
  ms_strbuild_append_text(&statement, "import ");
  ms_strbuild_append(&statement, name);
  ms_strbuild_append_text(&statement, " from \"");
  ms_strbuild_append(&statement, path);
  ms_strbuild_append_byte(&statement, '"');
  LspPosition at;
  MsStrBuild inserted = ms_strbuild_new();
  lsp_import_insertion(c->source, c->tree, ms_strbuild_span(&statement), &at, &inserted);
  MsStrBuild edit = ms_strbuild_new();
  ms_strbuild_printf(&edit, "{\"range\":{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}},\"newText\":", at.line,
                     at.character, at.line, at.character);
  lsp_json_string(&edit, ms_strbuild_span(&inserted));
  ms_strbuild_append_byte(&edit, '}');
  MsStrBuild sort = ms_strbuild_new();
  ms_strbuild_append_text(&sort, "04_");
  ms_strbuild_append(&sort, name);
  Item entry = {.label = own(name), .detail = ms_strbuild_finish(&detail), .documentation = own(ms_string_span(&item->documentation)),
                .sort = ms_strbuild_finish(&sort), .insert = insert, .additional = ms_strbuild_finish(&edit), .kind = item->kind,
                .format = c->snippets && (contains(ms_string_span(&insert), "${") || contains(ms_string_span(&insert), "$0")) ? 2 : 1};
  item_list_push(&c->items, entry);
  ms_strbuild_free(&statement);
  ms_strbuild_free(&inserted);
}

/* Offers the exports of the module `text` (imported as `path`) that match the word. */
static void add_importable(Completer *c, MsSpan text, MsSpan path) {
  if (!name_matches(text, c->prefix)) return; /* the names would have to appear, in order, somewhere in the file */
  ImportableList found = {0};
  collect_importable(text, path, false, &found);
  for (size_t i = 0; i < found.len; i++) offer_importable(c, &found.ptr[i]);
  importable_list_release(&found);
}

/* The exports of every public bundled module, parsed once for the process (the library cannot change under a running
 * server), in module order. */
static ImportableList bundled_importable;
static bool bundled_collected;

static const ImportableList *bundled_exports(void) {
  if (bundled_collected) return &bundled_importable;
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  MsStrBuild path = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    if (!public_module(sources[i].name)) continue;
    ms_strbuild_clear(&path);
    ms_strbuild_append_text(&path, "@std/");
    ms_strbuild_append(&path, sources[i].name);
    collect_importable(sources[i].text, ms_strbuild_span(&path), true, &bundled_importable);
  }
  ms_strbuild_free(&path);
  bundled_collected = true;
  return &bundled_importable;
}

/* Names the bundled library and the project's other files export, offered with the import that makes them visible. */
void lsp_import_suggestions(Completer *c, const LspDocList *docs, const LspDoc *doc) {
  const ImportableList *bundled = bundled_exports();
  for (size_t i = 0; i < bundled->len; i++) offer_importable(c, &bundled->ptr[i]);
  MsArena arena = ms_arena_new();
  MsSpanList files = {0};
  lsp_workspace_files(&arena, ms_string_span(&doc->path), &files);
  MsStrBuild base = ms_strbuild_new();
  ms_path_dir(ms_string_span(&doc->path), &base);
  for (size_t i = 0; i < files.len; i++) {
    if (ms_span_equal(files.ptr[i], ms_string_span(&doc->path))) continue;
    MsSpan import_path;
    if (!lsp_relative_import(&arena, ms_strbuild_span(&base), files.ptr[i], &import_path)) continue;
    MsBytes bytes = {0};
    MsSpan text = {0};
    for (size_t d = 0; d < docs->len; d++) {
      if (ms_span_equal(ms_string_span(&docs->ptr[d].path), files.ptr[i])) text = ms_string_span(&docs->ptr[d].text);
    }
    const bool on_disk = text.ptr == NULL && ms_file_read(files.ptr[i], &bytes);
    if (on_disk) text = ms_bytes_span(&bytes);
    if (text.ptr != NULL) add_importable(c, text, import_path);
    if (on_disk) ms_bytes_free(&bytes);
  }
  ms_strbuild_free(&base);
  ms_span_list_free(&files);
  ms_arena_free(&arena);
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
      if ((bundled && ms_check_is_prelude_declaration(path, name)) || ms_span_list_contains(imported, name) || !name_matches(name, c->prefix)) continue;
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

/* The names an import in `doc` may start with (`@alias`, `@dependency`) and the directory each reaches. */
static bool project_names(MsArena *arena, const LspDoc *doc, MsManifest *manifest) {
  MsStrBuild base = ms_strbuild_new();
  ms_path_dir(ms_string_span(&doc->path), &base);
  const MsSpan root = lsp_project_root(arena, ms_arena_copy(arena, ms_strbuild_span(&base)));
  ms_strbuild_free(&base);
  const MsSpan file = ms_message_format(arena, "%S/ms.toml", root, (MsSpan){0});
  MsProjectError error;
  return ms_path_kind(file) == MS_PATH_FILE && ms_manifest_read(arena, file, manifest, &error);
}

static bool name_target(const MsManifest *manifest, MsSpan name, MsSpan *target) {
  return ms_manifest_find(&manifest->aliases, name, target) || ms_manifest_find(&manifest->deps, name, target);
}

/* The `.ms` files and directories of `directory` whose path, written after `directory_prefix`, starts with `prefix`. The
 * directory must lie inside `root`. */
static void list_directory(Completer *c, MsArena *arena, MsSpan directory, MsSpan root, MsSpan directory_prefix, MsSpan prefix) {
  MsStrBuild cleaned = ms_strbuild_new(), inside = ms_strbuild_new();
  ms_path_clean(&cleaned, directory);
  MsDirEntryList entries = {0};
  if (ms_path_relative(&inside, root, ms_strbuild_span(&cleaned)) && !ms_path_escapes(ms_strbuild_span(&inside)) &&
      ms_dir_list(ms_strbuild_span(&cleaned), &entries)) {
    if (entries.len > 1) qsort(entries.ptr, entries.len, sizeof(MsDirEntry), compare_entry);
    for (size_t i = 0; i < entries.len; i++) {
      const MsSpan name = ms_string_span(&entries.ptr[i].name);
      const MsSpan full = ms_message_format(arena, "%S%S", directory_prefix, name);
      MsStrBuild entry_path = ms_strbuild_new();
      ms_path_join(ms_strbuild_span(&cleaned), name, &entry_path);
      const bool is_directory = entries.ptr[i].kind == MS_PATH_DIRECTORY ||
                                (entries.ptr[i].kind == MS_PATH_SYMLINK && ms_dir_exists(ms_strbuild_span(&entry_path)));
      ms_strbuild_free(&entry_path);
      if (ms_span_starts_with(full, prefix) && (is_directory || ms_span_ends_with(name, ms_span_of_text(".ms")))) add_path(c, full, is_directory);
    }
  }
  ms_dir_entries_free(&entries);
  ms_strbuild_free(&cleaned);
  ms_strbuild_free(&inside);
}

/* The module paths that start with `prefix`: bundled modules, the project's `@` names and, after `./`, `../` or an `@` name's
 * slash, the entries of that directory. */
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
  MsArena arena = ms_arena_new();
  MsManifest manifest = {0};
  const bool has_manifest = project_names(&arena, doc, &manifest);
  if (has_manifest) {
    const ManifestNameList *lists[2] = {&manifest.aliases, &manifest.deps};
    for (size_t l = 0; l < 2; l++) {
      for (size_t i = 0; i < lists[l]->len; i++) {
        const MsManifestName *entry = &lists[l]->ptr[i];
        if (ms_span_starts_with(entry->name, prefix)) add_path(c, entry->name, ms_dir_exists(entry->target));
      }
    }
  }
  size_t slash = prefix.len;
  while (slash > 0 && prefix.ptr[slash - 1] != '/') slash--;
  const MsSpan directory_prefix = ms_span_of(prefix.ptr, slash);
  const bool relative = ms_span_starts_with(prefix, ms_span_of_text("./")) || ms_span_starts_with(prefix, ms_span_of_text("../"));
  const bool aliased = ms_span_starts_with(prefix, ms_span_of_text("@")) && !ms_span_starts_with(prefix, ms_span_of_text("@std/"));
  if (slash > 0 && relative) {
    MsStrBuild base = ms_strbuild_new(), joined = ms_strbuild_new();
    ms_path_dir(ms_string_span(&doc->path), &base);
    ms_path_join(ms_strbuild_span(&base), directory_prefix, &joined);
    const MsSpan root = lsp_project_root(&arena, ms_arena_copy(&arena, ms_strbuild_span(&base)));
    list_directory(c, &arena, ms_strbuild_span(&joined), root, directory_prefix, prefix);
    ms_strbuild_free(&base);
    ms_strbuild_free(&joined);
  } else if (slash > 0 && aliased && has_manifest) {
    /* `@lib/sub/` lists the directory of `@lib` below `sub/`. */
    const MsSpan trimmed = ms_span_of(prefix.ptr, slash - 1);
    size_t cut = 0;
    while (cut < trimmed.len && trimmed.ptr[cut] != '/') cut++;
    const MsSpan alias = ms_span_of(trimmed.ptr, cut);
    const MsSpan remainder = cut < trimmed.len ? ms_span_of(trimmed.ptr + cut + 1, trimmed.len - cut - 1) : (MsSpan){0};
    MsSpan target;
    if (name_target(&manifest, alias, &target) && ms_dir_exists(target)) {
      MsStrBuild joined = ms_strbuild_new();
      ms_path_join(target, remainder, &joined);
      list_directory(c, &arena, ms_strbuild_span(&joined), target, directory_prefix, prefix);
      ms_strbuild_free(&joined);
    }
  }
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
bool lsp_import_items(Completer *c, const LspDoc *doc, const LspDocList *docs) {
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
    qsort(c->items.ptr, c->items.len, sizeof(Item), lsp_completion_compare_item);
    return true;
  }
  MsSpanList imported = {0};
  imported_names(c, start, grouped, &imported);
  MsSpan path;
  if (following_path(c->source, c->end, braces, &path)) {
    if (ms_span_starts_with(path, ms_span_of_text("@std/"))) {
      MsStdSource source;
      if (ms_std_source_find(ms_span_of(path.ptr + 5, path.len - 5), &source)) add_exports(c, source.text, path, true, &imported, true, false);
    } else if (ms_span_starts_with(path, ms_span_of_text(".")) || ms_span_starts_with(path, ms_span_of_text("@"))) {
      MsArena arena = ms_arena_new();
      MsStrBuild base = ms_strbuild_new(), joined = ms_strbuild_new(), file = ms_strbuild_new();
      bool resolved = true;
      if (path.ptr[0] == '.') {
        ms_path_dir(ms_string_span(&doc->path), &base);
        ms_path_join(ms_strbuild_span(&base), path, &joined);
      } else {
        MsManifest manifest = {0};
        size_t cut = 0;
        while (cut < path.len && path.ptr[cut] != '/') cut++;
        MsSpan target;
        resolved = project_names(&arena, doc, &manifest) && name_target(&manifest, ms_span_of(path.ptr, cut), &target);
        if (resolved) ms_path_join(target, cut < path.len ? ms_span_of(path.ptr + cut + 1, path.len - cut - 1) : (MsSpan){0}, &joined);
      }
      ms_path_clean(&file, ms_strbuild_span(&joined));
      MsBytes bytes = {0};
      MsSpan text = {0};
      for (size_t i = 0; resolved && i < docs->len; i++) {
        if (ms_span_equal(ms_string_span(&docs->ptr[i].path), ms_strbuild_span(&file))) text = ms_string_span(&docs->ptr[i].text);
      }
      const bool on_disk = resolved && text.ptr == NULL && ms_file_read(ms_strbuild_span(&file), &bytes);
      if (on_disk) text = ms_bytes_span(&bytes);
      if (text.ptr != NULL) add_exports(c, text, path, false, &imported, true, false);
      if (on_disk) ms_bytes_free(&bytes);
      ms_strbuild_free(&base);
      ms_strbuild_free(&joined);
      ms_strbuild_free(&file);
      ms_arena_free(&arena);
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
  if (c->items.len > 1) qsort(c->items.ptr, c->items.len, sizeof(Item), lsp_completion_compare_item);
  return true;
}

/* The marked document's analysis and, from it, the items of the cursor's place. */
