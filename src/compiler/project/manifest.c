/* compiler/project/manifest.c: ms.toml validation, port of crates/ms-driver/src/project/manifest.rs for the
 * tables [project], [aliases] and [embed]. The TOML syntax errors are this reader's own wording. */
#include "compiler/project/manifest.h"
#include "compiler/project/manifest_internal.h"

#include <errno.h>

#include "base/file.h"
#include "base/path.h"


bool manifest_fail_at(Reader *r, MsPos at, MsSpan message) {
  *r->error = (MsProjectError){
      .kind = MS_PERR_MANIFEST, .file = r->out->file, .position = at, .message = message};
  return false;
}

bool manifest_fail_text(Reader *r, MsPos at, const char *message) {
  return manifest_fail_at(r, at, ms_arena_copy(r->arena, ms_span_of_text(message)));
}

/* A formatted message in the arena. */
MsSpan manifest_formatted(Reader *r, const char *format, MsSpan a, MsSpan b) {
  MsStrBuild text = ms_strbuild_new();
  for (const char *c = format; *c != 0; c++) {
    if (*c != '%') {
      ms_strbuild_append_byte(&text, (uint8_t)*c);
    } else if (*++c == 'a') {
      ms_strbuild_append(&text, a);
    } else {
      ms_strbuild_append(&text, b);
    }
  }
  return ms_project_text(r->arena, &text);
}

bool manifest_valid_alias(MsSpan key) {
  if (key.len < 2 || key.ptr[0] != '@') {
    return false;
  }
  for (size_t i = 1; i < key.len; i++) {
    const uint8_t c = key.ptr[i];
    const bool letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    if (!letter && !(i > 1 && c >= '0' && c <= '9')) {
      return false;
    }
  }
  return true;
}

static bool has_control(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] < 0x20 || text.ptr[i] == 0x7f) {
      return true;
    }
  }
  return false;
}

/* The string value of `entry`, or the error naming the shape the key wants. */
bool manifest_text_value(Reader *r, const TomlEntry *entry, MsSpan *value) {
  if (!entry->is_string) {
    MsSpan shown = entry->text;
    while (shown.len > 0 && shown.ptr[0] == '"') {
      shown = ms_span_of(shown.ptr + 1, shown.len - 1);
    }
    while (shown.len > 0 && shown.ptr[shown.len - 1] == '"') {
      shown.len--;
    }
    return manifest_fail_at(r, entry->value_at, manifest_formatted(r, "%a must be a string; write %a = \"%b\"", entry->key, shown));
  }
  if (has_control(entry->text)) {
    return manifest_fail_at(r, entry->value_at, manifest_formatted(r, "manifest value for %a contains a NUL or control character; remove it", entry->key, entry->key));
  }
  *value = entry->text;
  return true;
}

static bool unsupported_table(Reader *r, const TomlTable *table) {
  const bool package = ms_span_is_text(table->name, "package");
  return manifest_fail_at(r, table->at,
                 manifest_formatted(r,
                           "unsupported manifest table [%a]; ms.toml supports only [project], [workspace], "
                           "[aliases], [embed], [dependencies] and [effects]: %b",
                           table->name,
                           ms_span_of_text(package ? "rename it to [project] with name, source, and entry"
                                                   : "ms.toml has no other tables")));
}

static bool project_entry(Reader *r, const TomlEntry *entry) {
  const MsSpan key = entry->key;
  if (!ms_span_is_text(key, "name") && !ms_span_is_text(key, "source") && !ms_span_is_text(key, "entry") &&
      !ms_span_is_text(key, "version") && !ms_span_is_text(key, "effects")) {
    return manifest_fail_at(r, entry->key_at,
                            manifest_formatted(r, "unknown project key %a; [project] accepts name, source, entry, "
                                                  "version, and effects", key, key));
  }
  if (ms_span_is_text(key, "effects")) {
    return manifest_project_effects(r, entry);
  }
  MsSpan value = {0};
  if (!manifest_text_value(r, entry, &value)) {
    return false;
  }
  if (ms_span_is_text(key, "version")) {
    return manifest_project_version(r, entry, value);
  }
  if (ms_span_is_text(key, "name")) {
    r->out->name = value;
  } else if (ms_span_is_text(key, "source")) {
    r->out->source = value;
  } else {
    r->out->entry = value;
  }
  return true;
}

static bool name_entry(Reader *r, const TomlEntry *entry, bool embed) {
  const MsSpan key = entry->key;
  if (!manifest_valid_alias(key) || ms_span_is_text(key, "@std")) {
    if (embed) {
      return manifest_fail_at(r, entry->key_at,
                     manifest_formatted(r, "invalid or reserved embed name %a; embed names look like @assets (start with @, "
                                  "letters/digits/underscore) and cannot be @std", key, key));
    }
    MsSpan hint = {0};
    MsStrBuild at_key = ms_strbuild_new();
    ms_strbuild_append_byte(&at_key, '@');
    ms_strbuild_append(&at_key, key);
    if (!ms_span_is_text(key, "std") && manifest_valid_alias(ms_strbuild_span(&at_key))) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, " (did you mean @");
      ms_strbuild_append(&text, key);
      ms_strbuild_append_text(&text, "?)");
      hint = ms_project_text(r->arena, &text);
    }
    ms_strbuild_free(&at_key);
    return manifest_fail_at(r, entry->key_at,
                   manifest_formatted(r, "invalid or reserved alias %a%b; aliases look like @lib (start with @, "
                                "letters/digits/underscore), cannot be @std, and must map to a path, not another alias",
                             key, hint));
  }
  MsSpan value = {0};
  if (!manifest_text_value(r, entry, &value)) {
    return false;
  }
  if (value.len > 0 && value.ptr[0] == '@') {
    return manifest_fail_at(r, entry->value_at,
                   embed ? manifest_formatted(r, "invalid embed target %a; map it to a project-local directory, not an alias", value, value)
                         : manifest_formatted(r, "invalid alias target %a; map it to a project-local path, not another alias", value, value));
  }
  manifest_name_list_push(embed ? &r->out->embeds : &r->out->aliases, (MsManifestName){.name = key, .target = value});
  return true;
}

static bool section_entries(Reader *r, int32_t index, const TomlTable *table) {
  const MsSpan name = table->name;
  for (size_t i = 0; i < r->document->entries.len; i++) {
    const TomlEntry *entry = &r->document->entries.ptr[i];
    if (entry->table != index) {
      continue;
    }
    bool ok = false;
    if (ms_span_is_text(name, "project")) {
      ok = project_entry(r, entry);
    } else if (ms_span_is_text(name, "aliases") || ms_span_is_text(name, "embed")) {
      ok = name_entry(r, entry, ms_span_is_text(name, "embed"));
    } else {
      ok = manifest_package_entry(r, table, entry);
    }
    if (!ok) {
      return false;
    }
  }
  return true;
}

/* Table headers and the keys under them, in document order, as the Rust reader walks them. */
static bool read_tables(Reader *r) {
  const TomlEntryList *entries = &r->document->entries;
  if (entries->len > 0 && entries->ptr[0].table < 0) {
    return manifest_fail_at(r, (MsPos){.line = 1, .column = 1},
                   manifest_formatted(r, "invalid manifest assignment; %a is not a table, so put it under a [project] table "
                                "header: ms.toml starts with [project] and name = \"app\" and source = \"src\" under it",
                             entries->ptr[0].key, entries->ptr[0].key));
  }
  for (size_t t = 0; t < r->document->tables.len; t++) {
    const TomlTable *table = &r->document->tables.ptr[t];
    const bool known = ms_span_is_text(table->name, "project") || ms_span_is_text(table->name, "aliases") ||
                       ms_span_is_text(table->name, "embed") || ms_span_is_text(table->name, "dependencies") ||
                       ms_span_is_text(table->name, "effects") || ms_span_is_text(table->name, "workspace");
    if (!known) {
      return unsupported_table(r, table);
    }
    r->out->is_workspace = r->out->is_workspace || ms_span_is_text(table->name, "workspace");
    if (ms_span_is_text(table->name, "project")) {
      r->out->location = table->at;
    }
    if (!section_entries(r, (int32_t)t, table)) {
      return false;
    }
  }
  return true;
}

const TomlEntry *manifest_find_entry(const Reader *r, const char *table, MsSpan key) {
  for (size_t i = 0; i < r->document->entries.len; i++) {
    const TomlEntry *entry = &r->document->entries.ptr[i];
    if (entry->table >= 0 && ms_span_is_text(r->document->tables.ptr[entry->table].name, table) &&
        ms_span_equal(entry->key, key)) {
      return entry;
    }
  }
  return NULL;
}

static MsSpan quoted(Reader *r, MsSpan text) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_byte(&out, '"');
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '"' || text.ptr[i] == '\\') {
      ms_strbuild_append_byte(&out, '\\');
    }
    ms_strbuild_append_byte(&out, text.ptr[i]);
  }
  ms_strbuild_append_byte(&out, '"');
  return ms_project_text(r->arena, &out);
}

/* Canonicalises `path` inside the manifest root. */
static bool resolve(Reader *r, MsSpan path, MsSpan *canonical, MsProjectError *cause) {
  return ms_project_source_path(r->arena, r->out->root, path, NULL, canonical, cause);
}

/* A path named in ms.toml that cannot be read: the fix is in the manifest, not the shell. */
static MsSpan manifest_path_message(Reader *r, const MsProjectError *cause) {
  const MsSpan message = ms_project_explain(r->arena, cause, (MsSpan){0});
  size_t at = 0;
  if (!ms_span_find(message, ms_span_of_text("; check the path, pass a .ms file"), &at)) {
    return message;
  }
  MsSpan head = ms_span_of(message.ptr, at);
  const MsSpan missing = ms_span_of_text("file not found:");
  MsStrBuild text = ms_strbuild_new();
  if (ms_span_starts_with(head, missing)) {
    ms_strbuild_append_text(&text, "path does not exist:");
    head = ms_span_of(head.ptr + missing.len, head.len - missing.len);
  }
  ms_strbuild_append(&text, head);
  ms_strbuild_append_text(&text, "; this path comes from ms.toml, so create it or correct the value there");
  return ms_project_text(r->arena, &text);
}

static bool check_source(Reader *r) {
  MsManifest *m = r->out;
  const TomlEntry *entry = manifest_find_entry(r, "project", ms_span_of_text("source"));
  MsProjectError cause = {0};
  if (!resolve(r, m->source, &m->source, &cause)) {
    return manifest_fail_at(r, entry->value_at, manifest_path_message(r, &cause));
  }
  if (!ms_dir_exists(m->source)) {
    return manifest_fail_at(r, entry->value_at,
                   manifest_formatted(r, "project source must be an existing directory; %a does not exist or is not a directory, "
                                "so create it or fix source in [project]", quoted(r, m->source), m->source));
  }
  return true;
}

static bool check_entry(Reader *r) {
  MsManifest *m = r->out;
  const TomlEntry *entry = manifest_find_entry(r, "project", ms_span_of_text("entry"));
  if (entry == NULL) {
    return true;
  }
  if (m->entry.len == 0) {
    return manifest_fail_text(r, entry->value_at, "project entry cannot be empty; omit entry for a library or set it to a .ms file such as \"src/main.ms\"");
  }
  MsProjectError cause = {0};
  if (!resolve(r, m->entry, &m->entry, &cause)) {
    return manifest_fail_at(r, entry->value_at, manifest_path_message(r, &cause));
  }
  if (!ms_span_is_text(ms_path_ext(m->entry), ".ms")) {
    return manifest_fail_text(r, entry->value_at, "entry requires .ms extension; set entry to a .ms file such as \"src/main.ms\"");
  }
  if (!ms_file_is_regular(m->entry)) {
    return manifest_fail_at(r, entry->value_at,
                   manifest_formatted(r, "project entry must be an existing regular file; create %a or fix entry in [project]", m->entry, m->entry));
  }
  return true;
}

static bool check_aliases(Reader *r) {
  for (size_t i = 0; i < r->out->aliases.len; i++) {
    MsManifestName *alias = &r->out->aliases.ptr[i];
    const TomlEntry *entry = manifest_find_entry(r, "aliases", alias->name);
    MsProjectError cause = {0};
    if (!resolve(r, alias->target, &alias->target, &cause)) {
      return manifest_fail_at(r, entry->value_at,
                     manifest_formatted(r, "alias %a target cannot be resolved: %b; external Manuscript dependency projects are "
                                  "unsupported, so copy the sources inside this project root and point the alias at that copy",
                               alias->name, ms_project_error_text(r->arena, &cause)));
    }
  }
  return true;
}

static bool check_embeds(Reader *r) {
  for (size_t i = 0; i < r->out->embeds.len; i++) {
    MsManifestName *embed = &r->out->embeds.ptr[i];
    const TomlEntry *entry = manifest_find_entry(r, "embed", embed->name);
    MsSpan unused = {0};
    if (ms_manifest_find(&r->out->aliases, embed->name, &unused)) {
      return manifest_fail_at(r, entry->key_at,
                     manifest_formatted(r, "%a is declared in both [aliases] and [embed]; rename one so an import names a single thing", embed->name, embed->name));
    }
    MsProjectError cause = {0};
    const bool resolved = resolve(r, embed->target, &embed->target, &cause);
    if (!resolved) {
      return manifest_fail_at(r, entry->value_at,
                     manifest_formatted(r, "embed %a target cannot be resolved: %b; keep embedded directories inside the project root",
                               embed->name, ms_project_error_text(r->arena, &cause)));
    }
    if (!ms_dir_exists(embed->target)) {
      return manifest_fail_at(r, entry->value_at,
                     manifest_formatted(r, "embed %a must name an existing directory; %b is not one, so create it or fix the path in [embed]",
                               embed->name, quoted(r, embed->target)));
    }
  }
  return true;
}

/* The first entry, by its `table.key` name, outside [workspace]; a root that lists members holds nothing else. */
static const TomlEntry *first_foreign_entry(const Reader *r) {
  const TomlEntry *first = NULL;
  for (size_t i = 0; i < r->document->entries.len; i++) {
    const TomlEntry *entry = &r->document->entries.ptr[i];
    const MsSpan table = r->document->tables.ptr[entry->table].name;
    if (ms_span_is_text(table, "workspace")) {
      continue;
    }
    if (first == NULL) {
      first = entry;
      continue;
    }
    const MsSpan held = r->document->tables.ptr[first->table].name;
    const size_t common = table.len < held.len ? table.len : held.len;
    int order = common == 0 ? 0 : __builtin_memcmp(table.ptr, held.ptr, common);
    if (order == 0 && table.len == held.len) {
      const size_t keys = entry->key.len < first->key.len ? entry->key.len : first->key.len;
      order = keys == 0 ? 0 : __builtin_memcmp(entry->key.ptr, first->key.ptr, keys);
      order = order != 0 ? order : (entry->key.len < first->key.len ? -1 : entry->key.len > first->key.len);
    } else if (order == 0) {
      order = table.len < held.len ? -1 : 1;
    }
    first = order < 0 ? entry : first;
  }
  return first;
}

static bool has_project_entry(const Reader *r) {
  for (size_t i = 0; i < r->document->entries.len; i++) {
    if (ms_span_is_text(r->document->tables.ptr[r->document->entries.ptr[i].table].name, "project")) {
      return true;
    }
  }
  return false;
}

typedef enum RootCheck { ROOT_PROJECT, ROOT_ONLY_MEMBERS, ROOT_INVALID } RootCheck;

/* A workspace root without [project] holds only [workspace] and needs no source of its own. */
static RootCheck check_workspace_root(Reader *r) {
  if (!r->out->is_workspace || has_project_entry(r)) {
    return ROOT_PROJECT;
  }
  const TomlEntry *extra = first_foreign_entry(r);
  if (extra != NULL) {
    (void)manifest_fail_at(r, extra->key_at,
                            manifest_formatted(r, "a workspace root without [project] holds only [workspace]; move [%a] "
                                                  "into a member or add a [project] table",
                                               r->document->tables.ptr[extra->table].name,
                                               r->document->tables.ptr[extra->table].name));
    return ROOT_INVALID;
  }
  return ROOT_ONLY_MEMBERS;
}

static bool check_project(Reader *r) {
  const MsManifest *m = r->out;
  const RootCheck root = check_workspace_root(r);
  if (root != ROOT_PROJECT) {
    return root == ROOT_ONLY_MEMBERS;
  }
  if (m->name.len == 0 || m->source.len == 0) {
    MsStrBuild missing = ms_strbuild_new();
    ms_strbuild_append_text(&missing, m->name.len == 0 ? "name" : "");
    ms_strbuild_append_text(&missing, m->name.len == 0 && m->source.len == 0 ? ", " : "");
    ms_strbuild_append_text(&missing, m->source.len == 0 ? "source" : "");
    return manifest_fail_at(r, m->location,
                            manifest_formatted(r, "[project] requires name and source; missing: %a, e.g. name = \"app\", "
                                                  "source = \"src\" (add entry = \"src/main.ms\" for an executable)",
                                               ms_project_text(r->arena, &missing), m->name));
  }
  return check_source(r) && check_entry(r) && check_aliases(r) && manifest_check_packages(r) && check_embeds(r);
}

bool ms_manifest_find(const ManifestNameList *list, MsSpan name, MsSpan *target) {
  for (size_t i = 0; i < list->len; i++) {
    if (ms_span_equal(list->ptr[i].name, name)) {
      *target = list->ptr[i].target;
      return true;
    }
  }
  return false;
}

static bool read_document(Reader *r, TomlDocument *document) {
  MsManifest *m = r->out;
  const bool bom = m->configuration.len >= 3 && m->configuration.ptr[0] == 0xEF && m->configuration.ptr[1] == 0xBB &&
                   m->configuration.ptr[2] == 0xBF;
  const MsSpan text = ms_span_of(m->configuration.ptr + (bom ? 3 : 0), m->configuration.len - (bom ? 3 : 0));
  MsPos at = {0};
  MsSpan message = {0};
  if (!toml_parse(r->arena, text, bom ? 3 : 0, document, &at, &message)) {
    return manifest_fail_at(r, at, message);
  }
  return true;
}

bool ms_manifest_read(MsArena *arena, MsSpan filename, MsManifest *out, MsProjectError *error) {
  *out = (MsManifest){.location = {.offset = 0, .line = 1, .column = 1}};
  out->file = ms_path_file_name(filename);
  MsString real = ms_string_empty();
  const MsSpan directory = ms_path_parent(filename);
  if (!ms_file_real_path(directory.len == 0 ? ms_span_of_text("/") : directory, &real)) {
    ms_project_error_path(error, "lstat", directory, errno);
    return false;
  }
  out->root = ms_arena_copy(arena, ms_string_span(&real));
  ms_string_release(&real);
  MsBytes bytes = {0};
  if (!ms_file_read(filename, &bytes)) {
    ms_project_error_path(error, "open", filename, errno);
    return false;
  }
  out->configuration = ms_arena_copy(arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  TomlDocument document = {0};
  Reader reader = {.arena = arena, .out = out, .document = &document, .error = error};
  bool ok = read_document(&reader, &document) && read_tables(&reader);
  manifest_sort_packages(out);
  ok = ok && check_project(&reader);
  toml_free(&document);
  return ok;
}

void ms_manifest_free(MsManifest *manifest) {
  manifest_name_list_free(&manifest->aliases);
  manifest_name_list_free(&manifest->embeds);
  dependency_list_free(&manifest->dependencies);
  manifest_name_list_free(&manifest->path_dependencies);
  allowed_effects_list_free(&manifest->allowed_effects);
  manifest_span_list_free(&manifest->members);
}
