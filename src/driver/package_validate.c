/* Owns the checks on a downloaded package (package_validate.h). */
#include "driver/package_validate.h"

#include "base/dir.h"
#include "base/message.h"
#include "base/path.h"
#include "compiler/project/manifest.h"
#include "compiler/project/project.h"

static bool is_reserved(MsSpan name) {
  static const char *const reserved[] = {"con",  "prn",  "aux",  "nul",  "com1", "com2", "com3", "com4",
                                         "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3",
                                         "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"};
  size_t stem = 0;
  while (stem < name.len && name.ptr[stem] != '.') {
    stem++;
  }
  MsStrBuild lower = ms_strbuild_new();
  for (size_t i = 0; i < stem; i++) {
    const uint8_t b = name.ptr[i];
    ms_strbuild_append_byte(&lower, b >= 'A' && b <= 'Z' ? (uint8_t)(b + 32) : b);
  }
  bool found = false;
  for (size_t i = 0; i < sizeof reserved / sizeof reserved[0]; i++) {
    found = found || ms_span_is_text(ms_strbuild_span(&lower), reserved[i]);
  }
  ms_strbuild_free(&lower);
  return found;
}

/* Whether Windows can create a file or directory called `name`. */
static bool portable_name(MsSpan name) {
  if (name.len > 0 && (name.ptr[name.len - 1] == '.' || name.ptr[name.len - 1] == ' ')) {
    return false;
  }
  for (size_t i = 0; i < name.len; i++) {
    const uint8_t b = name.ptr[i];
    const bool bad = b < 0x20 || b == 0x7f || b == '<' || b == '>' || b == ':' || b == '"' || b == '\\' ||
                     b == '|' || b == '?' || b == '*';
    if (bad) {
      return false;
    }
  }
  return !is_reserved(name);
}

/* The first component of `path` Windows cannot create, or an empty span. */
static MsSpan unportable_part(MsSpan path) {
  size_t start = 0;
  for (size_t i = 0; i <= path.len; i++) {
    if (i == path.len || path.ptr[i] == '/') {
      const MsSpan part = ms_span_of(path.ptr + start, i - start);
      if (!portable_name(part)) {
        return part;
      }
      start = i + 1;
    }
  }
  return (MsSpan){0};
}

static MsSpan lowered(MsArena *arena, MsSpan text) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t b = text.ptr[i];
    ms_strbuild_append_byte(&out, b >= 'A' && b <= 'Z' ? (uint8_t)(b + 32) : b);
  }
  const MsSpan copy = ms_message_from_builder(arena, &out);
  ms_strbuild_free(&out);
  return copy;
}

typedef struct Seen {
  MsSpan lower;
  MsSpan path;
} Seen;

MS_LIST_DEFINE(SeenList, seen_list, Seen)

/* Checks one `ls-files --stage` entry (`meta\tpath`). False with the error set. */
static bool check_entry(MsArena *arena, MsSpan key, MsSpan entry, SeenList *seen, MsSpan *error) {
  size_t tab = 0;
  while (tab < entry.len && entry.ptr[tab] != '\t') {
    tab++;
  }
  if (tab == entry.len) {
    return true;
  }
  const MsSpan meta = ms_span_of(entry.ptr, tab);
  const MsSpan path = ms_span_of(entry.ptr + tab + 1, entry.len - tab - 1);
  if (ms_span_starts_with(meta, ms_span_of_text("120000 "))) {
    *error = ms_message_format(arena,
                               "package %S: package contains the symbolic link %S; a package holds regular files "
                               "only",
                               key, path);
    return false;
  }
  const MsSpan part = unportable_part(path);
  if (part.len != 0) {
    *error = ms_message_format(arena, "package %S: %S has the name \"%S\", which Windows cannot create; rename it",
                               key, path, part);
    return false;
  }
  const MsSpan lower = lowered(arena, path);
  for (size_t i = 0; i < seen->len; i++) {
    if (ms_span_equal(seen->ptr[i].lower, lower)) {
      *error = ms_message_format(arena,
                                 "package %S: %S and %S differ only by letter case, so one overwrites the other on "
                                 "macOS and Windows; rename one",
                                 key, seen->ptr[i].path, path);
      return false;
    }
  }
  seen_list_push(seen, (Seen){.lower = lower, .path = path});
  return true;
}

bool ms_package_reject_unportable(MsGit *git, MsSpan key, MsSpan directory, const char *protocols, MsSpan *error) {
  static const char *const args[] = {"ls-files", "-z", "--stage"};
  MsSpan listing = {0};
  if (!ms_git_run(git, directory, protocols, args, 3, &listing, error)) {
    return false;
  }
  SeenList seen = {0};
  bool ok = true;
  size_t start = 0;
  for (size_t i = 0; ok && i <= listing.len; i++) {
    if (i == listing.len || listing.ptr[i] == 0) {
      ok = check_entry(git->arena, key, ms_span_of(listing.ptr + start, i - start), &seen, error);
      start = i + 1;
    }
  }
  seen_list_free(&seen);
  return ok;
}

/* The message with each `<directory>/` removed, so paths read from the package root. */
static MsSpan without_directory(MsArena *arena, MsSpan message, MsSpan directory) {
  const MsSpan prefix = ms_message_format(arena, "%S/", directory);
  MsStrBuild out = ms_strbuild_new();
  size_t at = 0;
  while (at < message.len) {
    if (ms_span_starts_with(ms_span_of(message.ptr + at, message.len - at), prefix)) {
      at += prefix.len;
    } else {
      ms_strbuild_append_byte(&out, message.ptr[at++]);
    }
  }
  const MsSpan copy = ms_message_from_builder(arena, &out);
  ms_strbuild_free(&out);
  return copy;
}

static bool check_top_level(MsArena *arena, MsSpan key, MsSpan directory, MsSpan *error) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(directory, &entries)) {
    *error = ms_message_format(arena, "read %S: cannot list it", directory);
    return false;
  }
  bool ok = true;
  for (size_t i = 0; ok && i < entries.len; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    if (name.len > 0 && name.ptr[0] == '@') {
      *error = ms_message_format(arena,
                                 "package %S has a top-level \"%S\"; rename it, names starting with @ are reserved "
                                 "for packages",
                                 key, name);
      ok = false;
    }
  }
  ms_dir_entries_free(&entries);
  return ok;
}

bool ms_package_validate(MsArena *arena, MsSpan key, MsSpan directory, MsSpan *error) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, directory, ms_span_of_text("ms.toml"));
  const MsSpan manifest_path = ms_message_from_builder(arena, &path);
  ms_strbuild_free(&path);
  if (ms_path_kind(manifest_path) != MS_PATH_FILE) {
    *error = ms_message_format(arena, "package %S has no ms.toml at its root", key);
    return false;
  }
  MsManifest manifest = {0};
  MsProjectError problem = {0};
  if (!ms_manifest_read(arena, manifest_path, &manifest, &problem)) {
    *error = ms_message_format(arena, "package %S: %S", key,
                               without_directory(arena, ms_project_error_text(arena, &problem), directory));
    return false;
  }
  if (manifest.entry.len != 0) {
    *error = ms_message_format(arena, "package %S has an entry; a package is a library, so remove entry", key);
    return false;
  }
  if (manifest.embeds.len != 0) {
    *error = ms_message_format(arena, "package %S declares [embed]; a package holds source only", key);
    return false;
  }
  return check_top_level(arena, key, directory, error);
}
