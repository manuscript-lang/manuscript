/* compiler/project/manifest_packages.c: the [dependencies], [effects] and [workspace] tables and the project keys
 * that go with them. Port of the matching parts of crates/ms-driver/src/project/manifest.rs. */
#include <errno.h>

#include "base/file.h"
#include "base/path.h"
#include "base/string.h"
#include "base/sort.h"
#include "base/message.h"
#include "compiler/project/manifest_internal.h"
#include "compiler/project/package.h"

/* What a manifest string list holds, for its errors and what it may contain. */
typedef struct ListKind {
  const char *noun, *plural, *example, *sample;
  bool spaces; /* directory names may hold spaces; effect patterns may not */
} ListKind;

static const ListKind EFFECT_LIST = {"effect", "effects", "[\"std.net.*\", \"std.fs.read\"]", "\"std.net.*\"", false};
static const ListKind MEMBER_LIST = {"member", "members", "[\"app\", \"libs/*\"]", "\"app\"", true};

static MsSpan text_of(Reader *r, MsStrBuild *builder) {
  return ms_message_take_builder(r->arena, builder);
}

static MsSpan list_shape(Reader *r, const ListKind *kind) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, kind->plural);
  ms_strbuild_append_text(&text, " are a list of strings: ");
  ms_strbuild_append_text(&text, kind->example);
  return text_of(r, &text);
}

static bool bad_list_char(const ListKind *kind, uint8_t c) {
  return c < 0x20 || c == 0x7f || (!kind->spaces && c == ' ');
}

static bool contains_text(const MsSpan *items, size_t count, MsSpan text) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_equal(items[i], text)) {
      return true;
    }
  }
  return false;
}

/* The element `text` of a string list when it is acceptable, else the message in `*why`. */
static bool list_element(Reader *r, const ListKind *kind, MsSpan text, const MsSpan *seen, size_t count, MsSpan *why) {
  bool bad = text.len == 0;
  for (size_t i = 0; i < text.len; i++) {
    bad = bad || bad_list_char(kind, text.ptr[i]);
  }
  MsStrBuild message = ms_strbuild_new();
  if (bad) {
    ms_strbuild_append_text(&message, "invalid ");
    ms_strbuild_append_text(&message, kind->noun);
    ms_strbuild_append_byte(&message, ' ');
    ms_strbuild_append(&message, ms_project_quote(r->arena, text));
    ms_strbuild_append_text(&message, kind->spaces ? "; write one directory per string, such as "
                                                   : "; write one pattern per string, such as ");
    ms_strbuild_append_text(&message, kind->sample);
  } else if (contains_text(seen, count, text)) {
    ms_strbuild_append_text(&message, kind->noun);
    ms_strbuild_append_byte(&message, ' ');
    ms_strbuild_append(&message, text);
    ms_strbuild_append_text(&message, " is listed twice; remove one");
  } else {
    ms_strbuild_free(&message);
    return true;
  }
  *why = text_of(r, &message);
  return false;
}

/* An array of strings, such as the effects `["std.net.*", "std.fs.read"]`. */
static bool string_list(Reader *r, const TomlEntry *entry, const ListKind *kind, const MsSpan **out, size_t *count,
                        MsSpan *why) {
  if (entry->kind != TOML_ARRAY) {
    *why = list_shape(r, kind);
    return false;
  }
  MsSpan *items = MS_ARENA_NEW_ARRAY(r->arena, MsSpan, entry->count == 0 ? 1 : entry->count);
  for (size_t i = 0; i < entry->count; i++) {
    const TomlValue *element = &r->document->values.ptr[entry->first + i];
    if (!element->is_string) {
      *why = list_shape(r, kind);
      return false;
    }
    if (!list_element(r, kind, element->text, items, i, why)) {
      return false;
    }
    items[i] = element->text;
  }
  *out = items;
  *count = entry->count;
  return true;
}

/* `prefix: why`, as a manifest error at the entry's value. */
static bool fail_prefixed(Reader *r, MsPos at, MsSpan prefix, MsSpan why) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, prefix);
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append(&text, why);
  return manifest_fail_at(r, at, text_of(r, &text));
}

static bool check_package_name(Reader *r, const TomlEntry *entry) {
  if (manifest_valid_alias(entry->key) && !ms_span_is_text(entry->key, "@std")) {
    return true;
  }
  return manifest_fail_at(r, entry->key_at,
                          manifest_formatted(r, "invalid or reserved package name %a; names look like @pg (start with "
                                               "@, letters/digits/underscore) and cannot be @std",
                                             entry->key, entry->key));
}

bool manifest_project_effects(Reader *r, const TomlEntry *entry) {
  MsSpan why = {0};
  if (!string_list(r, entry, &EFFECT_LIST, &r->out->effects, &r->out->neffects, &why)) {
    return fail_prefixed(r, entry->value_at, ms_span_of_text("effects"), why);
  }
  return true;
}

bool manifest_project_version(Reader *r, const TomlEntry *entry, MsSpan text) {
  MsSpan why = {0};
  if (!ms_version_parse(r->arena, text, &r->out->version, &why)) {
    return fail_prefixed(r, entry->value_at, ms_span_of_text("version"), why);
  }
  r->out->has_version = true;
  return true;
}

/* ---- [dependencies] ---- */

static const char *const DEPENDENCY_SHAPE =
    "write { url = \"https://github.com/acme/pg.git\", version = \"1.0\" }, or tag = \"v1.0.0\" or sha = "
    "\"<40-digit commit>\" in place of version";

typedef struct Fields {
  bool has_url, has_tag, has_sha, has_version, has_path;
  MsSpan url, tag, sha, version, path;
} Fields;

static MsSpan shaped(Reader *r, MsSpan head, const char *middle) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, head);
  ms_strbuild_append_text(&text, middle);
  ms_strbuild_append_text(&text, DEPENDENCY_SHAPE);
  return text_of(r, &text);
}

static bool assign_field(Fields *fields, MsSpan name, MsSpan value) {
  struct {
    const char *name;
    bool *has;
    MsSpan *text;
  } table[] = {{"url", &fields->has_url, &fields->url},         {"tag", &fields->has_tag, &fields->tag},
               {"sha", &fields->has_sha, &fields->sha},         {"version", &fields->has_version, &fields->version},
               {"path", &fields->has_path, &fields->path}};
  for (size_t i = 0; i < sizeof table / sizeof table[0]; i++) {
    if (ms_span_is_text(name, table[i].name)) {
      *table[i].has = true;
      *table[i].text = value;
      return true;
    }
  }
  return false;
}

static bool read_fields(Reader *r, const TomlEntry *entry, Fields *fields, MsSpan *why) {
  for (size_t i = 0; i < entry->count; i++) {
    const TomlValue *field = &r->document->values.ptr[entry->first + i];
    if (!field->is_string) {
      *why = shaped(r, field->key, " must be a string; ");
      return false;
    }
    if (!assign_field(fields, field->key, field->text)) {
      *why = manifest_formatted(r, "unknown field %a; a dependency has url and one of version, tag or sha, or only path",
                                field->key, field->key);
      return false;
    }
  }
  return true;
}

/* A path dependency names another workspace member by directory. */
static bool path_dependency(Reader *r, const TomlEntry *entry, const Fields *fields, MsSpan *why) {
  if (fields->has_url || fields->has_tag || fields->has_sha || fields->has_version || fields->path.len == 0) {
    *why = ms_span_of_text("a path dependency has only path = \"../member\"");
    return false;
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, r->out->root, fields->path);
  const MsSpan target = ms_arena_copy(r->arena, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  MsString real = ms_string_empty();
  if (!ms_file_real_path(target, &real)) {
    MsProjectError cause = {0};
    ms_project_error_path(&cause, "lstat", target, errno);
    *why = manifest_formatted(r, "path %a cannot be resolved: %b", ms_project_quote(r->arena, fields->path),
                              ms_project_error_text(r->arena, &cause));
    return false;
  }
  const MsManifestName found = {.name = entry->key, .target = ms_arena_copy(r->arena, ms_string_span(&real))};
  ms_string_release(&real);
  manifest_name_list_push(&r->out->path_dependencies, found);
  return true;
}

static bool git_source(Reader *r, const Fields *fields, MsDependency *found, MsSpan *why) {
  const int named = fields->has_version + fields->has_tag + fields->has_sha;
  if (named != 1) {
    *why = shaped(r, ms_span_of_text("name exactly one of version, tag and sha"), "; ");
    return false;
  }
  if (fields->has_version) {
    found->kind = MS_SOURCE_VERSION;
    return ms_requirement_parse(r->arena, fields->version, &found->requirement, why);
  }
  if (fields->has_tag) {
    found->kind = MS_SOURCE_TAG;
    found->reference = fields->tag;
    return true;
  }
  found->kind = MS_SOURCE_SHA;
  found->reference = fields->sha;
  if (!ms_package_is_hex(fields->sha, 40)) {
    *why = ms_span_of_text("sha must be the full 40-digit lowercase commit");
    return false;
  }
  return true;
}

static bool git_dependency(Reader *r, const TomlEntry *entry, const Fields *fields, MsSpan *why) {
  if (!fields->has_url) {
    *why = shaped(r, ms_span_of_text("url is missing"), "; ");
    return false;
  }
  MsDependency found = {.name = entry->key, .url = fields->url};
  if (!git_source(r, fields, &found, why)) {
    return false;
  }
  /* A requirement has no tag to check yet; a url is checked the same way as a pinned spec. */
  MsStrBuild spec = ms_strbuild_new();
  ms_strbuild_append(&spec, found.url);
  ms_strbuild_append_byte(&spec, '#');
  ms_strbuild_append(&spec, found.kind == MS_SOURCE_VERSION ? ms_span_of_text("v0.0.0") : found.reference);
  const bool ok = ms_package_check_spec(r->arena, ms_strbuild_span(&spec), why);
  ms_strbuild_free(&spec);
  if (ok) {
    dependency_list_push(&r->out->dependencies, found);
  }
  return ok;
}

/* A dependency is a table with `url` and exactly one of `tag`, `sha` and `version`, or only `path`. */
static bool read_dependency(Reader *r, const TomlEntry *entry) {
  MsSpan why = {0};
  Fields fields = {0};
  bool ok = entry->kind == TOML_TABLE;
  if (!ok) {
    why = shaped(r, ms_span_of_text("a dependency is a table"), "; ");
  }
  ok = ok && read_fields(r, entry, &fields, &why);
  ok = ok && (fields.has_path ? path_dependency(r, entry, &fields, &why) : git_dependency(r, entry, &fields, &why));
  if (ok) {
    return true;
  }
  MsStrBuild prefix = ms_strbuild_new();
  ms_strbuild_append_text(&prefix, "dependency ");
  ms_strbuild_append(&prefix, entry->key);
  return fail_prefixed(r, entry->value_at, text_of(r, &prefix), why);
}

bool manifest_package_entry(Reader *r, const TomlTable *table, const TomlEntry *entry) {
  MsSpan why = {0};
  if (ms_span_is_text(table->name, "effects")) {
    MsAllowedEffects allowed = {.name = entry->key};
    if (!string_list(r, entry, &EFFECT_LIST, &allowed.patterns, &allowed.count, &why)) {
      return fail_prefixed(r, entry->value_at, entry->key, why);
    }
    allowed_effects_list_push(&r->out->allowed_effects, allowed);
    return check_package_name(r, entry);
  }
  if (ms_span_is_text(table->name, "workspace")) {
    if (!ms_span_is_text(entry->key, "members")) {
      return manifest_fail_at(r, entry->key_at,
                              manifest_formatted(r, "unknown workspace key %a; [workspace] accepts members", entry->key,
                                                 entry->key));
    }
    const MsSpan *members = NULL;
    size_t count = 0;
    if (!string_list(r, entry, &MEMBER_LIST, &members, &count, &why)) {
      return fail_prefixed(r, entry->value_at, ms_span_of_text("members"), why);
    }
    for (size_t i = 0; i < count; i++) {
      manifest_span_list_push(&r->out->members, members[i]);
    }
    return true;
  }
  return check_package_name(r, entry) && read_dependency(r, entry);
}

/* ---- checks over the whole manifest ---- */

static int64_t compare_names(const MsSpan a, const MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return a.len < b.len ? -1 : a.len > b.len;
}

static int64_t compare_dependencies(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return compare_names(((const MsDependency *)(const void *)a)->name, ((const MsDependency *)(const void *)b)->name);
}

static int64_t compare_named(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return compare_names(((const MsManifestName *)(const void *)a)->name, ((const MsManifestName *)(const void *)b)->name);
}

static int64_t compare_allowed(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return compare_names(((const MsAllowedEffects *)(const void *)a)->name,
                       ((const MsAllowedEffects *)(const void *)b)->name);
}

void manifest_sort_packages(MsManifest *m) {
  if (m->dependencies.len > 1) {
    ms_sort((uint8_t *)m->dependencies.ptr, m->dependencies.len, sizeof(MsDependency), compare_dependencies, NULL);
  }
  if (m->path_dependencies.len > 1) {
    ms_sort((uint8_t *)m->path_dependencies.ptr, m->path_dependencies.len, sizeof(MsManifestName), compare_named, NULL);
  }
  if (m->allowed_effects.len > 1) {
    ms_sort((uint8_t *)m->allowed_effects.ptr, m->allowed_effects.len, sizeof(MsAllowedEffects), compare_allowed, NULL);
  }
}

const MsDependency *ms_manifest_dependency(const MsManifest *manifest, MsSpan name) {
  for (size_t i = 0; i < manifest->dependencies.len; i++) {
    if (ms_span_equal(manifest->dependencies.ptr[i].name, name)) {
      return &manifest->dependencies.ptr[i];
    }
  }
  return NULL;
}

static bool collides(Reader *r, MsSpan name) {
  MsSpan unused = {0};
  if (!ms_manifest_find(&r->out->aliases, name, &unused) && !ms_manifest_find(&r->out->embeds, name, &unused)) {
    return false;
  }
  const TomlEntry *entry = manifest_find_entry(r, "dependencies", name);
  (void)manifest_fail_at(r, entry->key_at,
                         manifest_formatted(r, "%a is declared in [dependencies] and also as an alias or embed; "
                                              "rename one so an import names a single thing",
                                            name, name));
  return true;
}

static bool is_dependency(const MsManifest *m, MsSpan name) {
  MsSpan unused = {0};
  return ms_manifest_dependency(m, name) != NULL || ms_manifest_find(&m->path_dependencies, name, &unused);
}

bool manifest_check_packages(Reader *r) {
  const MsManifest *m = r->out;
  for (size_t i = 0; i < m->dependencies.len; i++) {
    if (collides(r, m->dependencies.ptr[i].name)) {
      return false;
    }
  }
  for (size_t i = 0; i < m->path_dependencies.len; i++) {
    if (collides(r, m->path_dependencies.ptr[i].name)) {
      return false;
    }
  }
  for (size_t i = 0; i < m->allowed_effects.len; i++) {
    const MsSpan name = m->allowed_effects.ptr[i].name;
    if (!is_dependency(m, name)) {
      const TomlEntry *entry = manifest_find_entry(r, "effects", name);
      return manifest_fail_at(r, entry->key_at,
                              manifest_formatted(r, "[effects] names %a, which is not under [dependencies]; remove it or "
                                                   "add the dependency",
                                                 name, name));
    }
  }
  return true;
}
