/* Owns ms.lock and the package cache of lock.h: ids, reading and writing the lock, the cache directory and the index
 * of a package tree. */
#include "compiler/project/lock.h"

#include "base/dir.h"
#include "base/env.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/sha256.h"
#include "base/sort.h"
#include "compiler/project/package.h"
#include "compiler/project/project_internal.h"

enum { kMaxPackageBytes = 64 << 20 };

static bool find_text(MsSpan text, const char *needle, size_t *at) {
  return ms_span_find(text, ms_span_of_text(needle), at);
}

MsSpan ms_lock_repo_key(MsArena *arena, MsSpan url) {
  size_t at = 0;
  bool local = false;
  MsSpan rest = url;
  if (find_text(url, "://", &at)) {
    local = ms_span_is_text(ms_span_of(url.ptr, at), "file");
    rest = ms_span_of(url.ptr + at + 3, url.len - at - 3);
  }
  while (rest.len > 0 && rest.ptr[rest.len - 1] == '/') {
    rest.len--;
  }
  if (ms_span_ends_with(rest, ms_span_of_text(".git"))) {
    rest.len -= 4;
  }
  if (local) {
    while (rest.len > 0 && rest.ptr[0] == '/') {
      rest = ms_span_of(rest.ptr + 1, rest.len - 1);
    }
    return ms_message_format(arena, "file/%S", rest);
  }
  size_t slash = 0;
  while (slash < rest.len && rest.ptr[slash] != '/') {
    slash++;
  }
  if (slash == rest.len) {
    return ms_message_lowered(arena, rest);
  }
  return ms_message_format(arena, "%S%S", ms_message_lowered(arena, ms_span_of(rest.ptr, slash)),
                           ms_span_of(rest.ptr + slash, rest.len - slash));
}

MsSpan ms_lock_copy_id(MsArena *arena, MsSpan url, MsSpan reference) {
  return ms_message_format(arena, "%S@%S", ms_lock_repo_key(arena, url), reference);
}

static bool split_spec(MsSpan spec, MsSpan *url, MsSpan *reference) {
  for (size_t i = 0; i < spec.len; i++) {
    if (spec.ptr[i] == '#') {
      *url = ms_span_of(spec.ptr, i);
      *reference = ms_span_of(spec.ptr + i + 1, spec.len - i - 1);
      return true;
    }
  }
  return false;
}

bool ms_lock_id_of_spec(MsArena *arena, MsSpan spec, MsSpan *id) {
  MsSpan url = {0};
  MsSpan reference = {0};
  if (!split_spec(spec, &url, &reference)) {
    return false;
  }
  *id = ms_lock_copy_id(arena, url, reference);
  return true;
}

bool ms_lock_entry_version(MsArena *arena, const MsLockEntry *entry, MsVersion *out) {
  MsSpan url = {0};
  MsSpan reference = {0};
  return split_spec(entry->spec, &url, &reference) && ms_version_of_tag(arena, reference, out);
}

/* ---- reading ---- */

static MsSpan trimmed(MsSpan text) {
  while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t' || text.ptr[0] == '\r')) {
    text = ms_span_of(text.ptr + 1, text.len - 1);
  }
  while (text.len > 0 &&
         (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\t' || text.ptr[text.len - 1] == '\r')) {
    text.len--;
  }
  return text;
}

static MsSpan unquoted(MsSpan text) {
  while (text.len > 0 && text.ptr[0] == '"') {
    text = ms_span_of(text.ptr + 1, text.len - 1);
  }
  while (text.len > 0 && text.ptr[text.len - 1] == '"') {
    text.len--;
  }
  return text;
}

/* The next whitespace-separated word of `*rest`, or false. */
static bool next_word(MsSpan *rest, MsSpan *word) {
  size_t start = 0;
  while (start < rest->len && rest->ptr[start] <= ' ') {
    start++;
  }
  if (start == rest->len) {
    return false;
  }
  size_t end = start;
  while (end < rest->len && rest->ptr[end] > ' ') {
    end++;
  }
  *word = ms_span_of(rest->ptr + start, end - start);
  *rest = ms_span_of(rest->ptr + end, rest->len - end);
  return true;
}

static bool key_is_clean(MsSpan key) {
  if (key.len == 0) {
    return false;
  }
  for (size_t i = 0; i < key.len; i++) {
    if (key.ptr[i] <= ' ' || key.ptr[i] == 0x7f) {
      return false;
    }
  }
  return true;
}

typedef struct LockLine {
  MsSpan key;
  MsSpan spec, revision, hash;
} LockLine;

/* Splits one lock line into its key and three words. False when it is not that shape. */
static bool split_line(MsSpan line, LockLine *out) {
  size_t eq = 0;
  while (eq < line.len && line.ptr[eq] != '=') {
    eq++;
  }
  if (eq == line.len) {
    return false;
  }
  out->key = unquoted(trimmed(ms_span_of(line.ptr, eq)));
  MsSpan value = unquoted(trimmed(ms_span_of(line.ptr + eq + 1, line.len - eq - 1)));
  MsSpan extra = {0};
  return key_is_clean(out->key) && next_word(&value, &out->spec) && next_word(&value, &out->revision) &&
         next_word(&value, &out->hash) && !next_word(&value, &extra);
}

static bool parse_line(MsArena *arena, size_t number, MsSpan raw, MsLockEntry *out, MsSpan *error) {
  LockLine line = {0};
  MsSpan hash = {0};
  if (!split_line(raw, &line) || !ms_span_starts_with(line.hash, ms_span_of_text("sha256:"))) {
    *error = ms_message_format(arena,
                               "ms.lock line %z is not `\"@name\" = \"url#tag revision sha256:hash\"`; delete "
                               "ms.lock and run ms install to pin again",
                               number);
    return false;
  }
  hash = ms_span_of(line.hash.ptr + 7, line.hash.len - 7);
  if (!ms_package_is_hex(line.revision, 40) || !ms_package_is_hex(hash, 64)) {
    *error = ms_message_format(arena,
                               "ms.lock line %z must hold a 40-digit commit and a 64-digit sha256, both lowercase "
                               "hexadecimal; delete ms.lock and run ms install to pin again",
                               number);
    return false;
  }
  MsSpan why = {0};
  if (!ms_package_check_spec(arena, line.spec, &why)) {
    *error = ms_message_format(arena, "ms.lock line %z: %S", number, why);
    return false;
  }
  MsSpan id = {0};
  if (!ms_lock_id_of_spec(arena, line.spec, &id) || !ms_span_equal(id, line.key)) {
    *error = ms_message_format(arena,
                               "ms.lock line %z is keyed %S, but its source is %S; delete ms.lock and run ms "
                               "install to pin again",
                               number, line.key, line.spec);
    return false;
  }
  *out = (MsLockEntry){.id = ms_arena_copy(arena, line.key), .spec = ms_arena_copy(arena, line.spec),
                       .revision = ms_arena_copy(arena, line.revision), .sha256 = ms_arena_copy(arena, hash)};
  return true;
}

static int64_t compare_entries(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan x = ((const MsLockEntry *)(const void *)a)->id;
  const MsSpan y = ((const MsLockEntry *)(const void *)b)->id;
  const size_t common = x.len < y.len ? x.len : y.len;
  for (size_t i = 0; i < common; i++) {
    if (x.ptr[i] != y.ptr[i]) {
      return x.ptr[i] < y.ptr[i] ? -1 : 1;
    }
  }
  return x.len == y.len ? 0 : (x.len < y.len ? -1 : 1);
}

static bool read_lines(MsArena *arena, MsSpan text, MsLockList *out, MsSpan *error) {
  size_t number = 0;
  size_t start = 0;
  while (start <= text.len) {
    size_t end = start;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    number++;
    const MsSpan line = trimmed(ms_span_of(text.ptr + start, end - start));
    start = end + 1;
    if (line.len == 0 || line.ptr[0] == '#') {
      continue;
    }
    MsLockEntry entry = {0};
    if (!parse_line(arena, number, line, &entry, error)) {
      return false;
    }
    for (size_t i = 0; i < out->len; i++) {
      if (ms_span_equal(out->ptr[i].id, entry.id)) {
        *error = ms_message_format(arena,
                                   "ms.lock line %z repeats %S; a merge may have kept both sides, so delete ms.lock "
                                   "and run ms install to pin again",
                                   number, entry.id);
        return false;
      }
    }
    ms_lock_list_push(out, entry);
  }
  return true;
}

bool ms_lock_read(MsArena *arena, MsSpan root, MsLockList *out, MsSpan *error) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, root, ms_span_of_text("ms.lock"));
  MsBytes bytes = {0};
  const MsSpan name = ms_message_from_builder(arena, &path);
  ms_strbuild_free(&path);
  if (ms_path_kind(name) == MS_PATH_MISSING) {
    return true;
  }
  if (!ms_file_read(name, &bytes)) {
    *error = ms_message_format(arena, "open %S: cannot read it", name);
    return false;
  }
  MsSpan text = ms_bytes_span(&bytes);
  if (ms_span_starts_with(text, ms_span_of((const uint8_t *)"\xEF\xBB\xBF", 3))) {
    text = ms_span_of(text.ptr + 3, text.len - 3);
  }
  const bool ok = read_lines(arena, text, out, error);
  ms_bytes_free(&bytes);
  if (ok) {
    ms_sort((uint8_t *)out->ptr, out->len, sizeof(MsLockEntry), compare_entries, NULL);
  }
  return ok;
}

MsSpan ms_lock_text(MsArena *arena, const MsLockEntry *entries, size_t count) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "# Written by `ms install`. Commit it: it pins each package to a commit and a "
                                 "content hash.\n");
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(&text, "\"");
    ms_strbuild_append(&text, entries[i].id);
    ms_strbuild_append_text(&text, "\" = \"");
    ms_strbuild_append(&text, entries[i].spec);
    ms_strbuild_append_byte(&text, ' ');
    ms_strbuild_append(&text, entries[i].revision);
    ms_strbuild_append_text(&text, " sha256:");
    ms_strbuild_append(&text, entries[i].sha256);
    ms_strbuild_append_text(&text, "\"\n");
  }
  const MsSpan copy = ms_message_from_builder(arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

/* ---- the cache ---- */

static bool env_text(const char *name, MsString *out) {
  return ms_env_get(name, out) && !ms_string_is_empty(out);
}

MsSpan ms_lock_cache_dir(MsArena *arena) {
  MsString base = ms_string_empty();
  MsSpan result = {0};
  if (env_text("MS_PACKAGE_CACHE", &base)) {
    result = ms_arena_copy(arena, ms_string_span(&base));
    ms_string_release(&base);
    return result;
  }
  bool found = false;
#ifdef _WIN32
  found = env_text("LOCALAPPDATA", &base);
#endif
  if (!found && env_text("XDG_CACHE_HOME", &base)) {
    found = true;
  }
  if (!found && env_text("HOME", &base)) {
    MsStrBuild home = ms_strbuild_new();
    ms_path_append_joined(&home, ms_string_span(&base), ms_span_of_text(".cache"));
    ms_string_release(&base);
    base = ms_string_from_span(ms_strbuild_span(&home));
    ms_strbuild_free(&home);
    found = true;
  }
  if (!found) {
    base = ms_temp_dir();
  }
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, ms_string_span(&base), ms_span_of_text("ms"));
  MsStrBuild full = ms_strbuild_new();
  ms_path_append_joined(&full, ms_strbuild_span(&path), ms_span_of_text("packages"));
  result = ms_message_from_builder(arena, &full);
  ms_strbuild_free(&full);
  ms_strbuild_free(&path);
  ms_string_release(&base);
  return result;
}

MsSpan ms_lock_index_path(MsArena *arena, MsSpan cache, MsSpan hash) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, cache, hash);
  ms_strbuild_append_text(&path, ".index");
  const MsSpan copy = ms_message_from_builder(arena, &path);
  ms_strbuild_free(&path);
  return copy;
}

/* ---- the index ---- */

typedef struct Collect {
  MsArena *arena;
  MsList files; /* of MsSpan, the `/` paths below the package root */
  MsSpan *error;
} Collect;

static bool collect_dir(Collect *c, MsSpan directory, MsSpan prefix);

static bool collect_entry(Collect *c, MsSpan directory, MsSpan prefix, const MsDirEntry *entry) {
  const MsSpan name = ms_string_span(&entry->name);
  if (prefix.len == 0 && ms_span_is_text(name, ".git")) {
    return true;
  }
  const MsSpan relative = ms_message_format(c->arena, "%S%S", prefix, name);
  if (entry->kind == MS_PATH_SYMLINK) {
    *c->error = ms_message_format(c->arena,
                                  "package contains the symbolic link %S; a package holds regular files only",
                                  relative);
    return false;
  }
  if (entry->kind == MS_PATH_DIRECTORY) {
    MsStrBuild child = ms_strbuild_new();
    ms_path_append_joined(&child, directory, name);
    const MsSpan path = ms_message_from_builder(c->arena, &child);
    ms_strbuild_free(&child);
    return collect_dir(c, path, ms_message_format(c->arena, "%S/", relative));
  }
  ms_list_push(&c->files, sizeof(MsSpan), &relative);
  return true;
}

static bool collect_dir(Collect *c, MsSpan directory, MsSpan prefix) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(directory, &entries)) {
    *c->error = ms_message_format(c->arena, "read directory %S: cannot list it", directory);
    return false;
  }
  bool ok = true;
  for (size_t i = 0; ok && i < entries.len; i++) {
    ok = collect_entry(c, directory, prefix, &entries.ptr[i]);
  }
  ms_dir_entries_free(&entries);
  return ok;
}

bool ms_lock_index_tree(MsArena *arena, MsSpan directory, MsSpan *index, MsSpan *error) {
  Collect c = {.arena = arena, .error = error};
  if (!collect_dir(&c, directory, (MsSpan){0})) {
    ms_list_free(&c.files);
    return false;
  }
  MsSpan *files = (MsSpan *)(void *)c.files.ptr;
  ms_sort((uint8_t *)files, c.files.len, sizeof(MsSpan), ms_sort_compare_spans, NULL);
  MsStrBuild text = ms_strbuild_new();
  size_t total = 0;
  bool ok = true;
  for (size_t i = 0; ok && i < c.files.len; i++) {
    MsStrBuild path = ms_strbuild_new();
    ms_path_append_joined(&path, directory, files[i]);
    MsBytes bytes = {0};
    if (!ms_file_read(ms_strbuild_span(&path), &bytes)) {
      *error = ms_message_format(arena, "read %S: cannot read it", files[i]);
      ok = false;
    } else {
      total += bytes.len;
      uint8_t digest[MS_SHA256_HEX_LEN];
      ms_sha256_hex(ms_bytes_span(&bytes), digest);
      ms_strbuild_append(&text, files[i]);
      ms_strbuild_append_byte(&text, 0);
      ms_strbuild_append(&text, ms_span_of(digest, sizeof(digest)));
      ms_strbuild_append_byte(&text, '\n');
      ms_bytes_free(&bytes);
      if (total > kMaxPackageBytes) {
        *error = ms_message_format(arena, "package is larger than %u MiB; a package holds source only",
                                   (unsigned)(kMaxPackageBytes >> 20));
        ok = false;
      }
    }
    ms_strbuild_free(&path);
  }
  ms_list_free(&c.files);
  if (ok) {
    *index = ms_message_from_builder(arena, &text);
  }
  ms_strbuild_free(&text);
  return ok;
}

MsSpan ms_lock_hash_index(MsArena *arena, MsSpan index) {
  uint8_t digest[MS_SHA256_HEX_LEN];
  ms_sha256_hex(index, digest);
  return ms_arena_copy(arena, ms_span_of(digest, sizeof(digest)));
}
