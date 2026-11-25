/* compiler/project/discover.c: the test and source modules of a project. Files come back as canonical-looking absolute paths in byte
 * order. Unsaved editor files are not added yet. */
#include <errno.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/path.h"
#include "base/sort.h"
#include "base/utf8.h"
#include "base/message.h"
#include "compiler/project/project_internal.h"

typedef struct Scan {
  MsArena *arena;
  MsSpan root;   /* the project root */
  MsSpan source; /* the source directory */
  bool include_source;
  MsSpanList *files;
  MsProjectError *error;
} Scan;

static bool is_test_name(MsSpan name) {
  return ms_span_is_text(name, "test.ms") || ms_span_ends_with_text(name, "_test.ms") ||
         ms_span_is_text(name, "bench.ms") || ms_span_ends_with_text(name, "_bench.ms");
}

bool ms_project_skips_name(MsSpan name) {
  return (name.len > 0 && name.ptr[0] == '.') || ms_span_is_text(name, "vendor") ||
         ms_span_is_text(name, "node_modules");
}

static bool is_nested_project(MsArena *arena, MsSpan directory) {
  MsStrBuild manifest = ms_strbuild_new();
  ms_path_append_joined(&manifest, directory, ms_span_of_text("ms.toml"));
  const bool nested = ms_file_is_regular(ms_strbuild_span(&manifest));
  ms_strbuild_free(&manifest);
  (void)arena;
  return nested;
}

/* A link to a directory is never followed. */
static bool is_directory_link(MsSpan path, MsPathKind kind) {
  return kind == MS_PATH_SYMLINK && ms_dir_exists(path);
}

static int64_t entry_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsDirEntry *x = (const void *)a;
  const MsDirEntry *y = (const void *)b;
  const MsSpan left = ms_string_span(&x->name);
  const MsSpan right = ms_string_span(&y->name);
  const int by_name = ms_span_compare(left, right);
  if (by_name != 0) {
    return by_name;
  }
  return (x->kind == MS_PATH_DIRECTORY) - (y->kind == MS_PATH_DIRECTORY);
}

enum { NESTED_DEPTH = 6, NESTED_SHOWN = 4 };

/* The directories below `dir` that hold their own ms.toml, as paths relative to the walk's start (`prefix`), not
 * descending into one. */
static void collect_nested(MsArena *arena, MsSpan dir, MsSpan prefix, size_t depth, MsSpanList *found) {
  MsDirEntryList entries = {0};
  if (depth > NESTED_DEPTH || !ms_dir_list(dir, &entries)) {
    return;
  }
  ms_sort((uint8_t *)entries.ptr, entries.len, sizeof(MsDirEntry), entry_order, NULL);
  for (size_t i = 0; i < entries.len; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    if (entries.ptr[i].kind != MS_PATH_DIRECTORY || ms_project_skips_name(name)) {
      continue;
    }
    const MsSpan path = ms_message_format(arena, "%S/%S", dir, name);
    const MsSpan shown = prefix.len == 0 ? name : ms_message_format(arena, "%S/%S", prefix, name);
    if (is_nested_project(arena, path)) {
      ms_span_list_push(found, ms_arena_copy(arena, shown));
    } else {
      collect_nested(arena, path, shown, depth + 1, found);
    }
  }
  ms_dir_entries_free(&entries);
}

MsSpan ms_project_nested_hint(MsArena *arena, MsSpan dir) {
  MsSpanList found = {0};
  collect_nested(arena, dir, (MsSpan){0}, 0, &found);
  if (found.len == 0) {
    return (MsSpan){0};
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "; it holds the projects ");
  for (size_t i = 0; i < found.len && i < NESTED_SHOWN; i++) {
    ms_strbuild_append_text(&text, i == 0 ? "" : ", ");
    ms_strbuild_append(&text, found.ptr[i]);
  }
  if (found.len > NESTED_SHOWN) {
    ms_strbuild_printf(&text, " and %zu more", found.len - NESTED_SHOWN);
  }
  ms_strbuild_append_text(&text, ", so name one's ms.toml or run the command inside one");
  const MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  ms_span_list_free(&found);
  return copy;
}

/* Whether a directory is entered: not the hidden, vendored or nested ones, but always the scan's own root. */
static bool enters(const Scan *scan, MsSpan scan_root, bool all, MsSpan path, MsSpan name) {
  if (scan->include_source && !all && ms_span_equal(path, scan->source)) {
    return false;
  }
  return ms_span_equal(path, scan_root) || ms_span_equal(path, scan->root) ||
         !(ms_project_skips_name(name) || is_nested_project(scan->arena, path));
}

static bool walk_entry(Scan *scan, MsSpan scan_root, bool all, MsSpan path, MsSpan name, bool is_dir);

static bool walk_children(Scan *scan, MsSpan scan_root, bool all, MsSpan path) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(path, &entries)) {
    ms_project_error_path(scan->error, "open", ms_arena_copy(scan->arena, path), errno);
    ms_dir_entries_free(&entries);
    return false;
  }
  ms_sort((uint8_t *)entries.ptr, entries.len, sizeof(MsDirEntry), entry_order, NULL);
  bool ok = true;
  for (size_t i = 0; ok && i < entries.len; i++) {
    const MsDirEntry *entry = &entries.ptr[i];
    const MsSpan name = ms_string_span(&entry->name);
    MsStrBuild child = ms_strbuild_new();
    ms_path_append_joined(&child, path, name);
    const MsSpan full = ms_message_take_builder(scan->arena, &child);
    if (is_directory_link(full, entry->kind)) {
      continue;
    }
    if (!ms_utf8_is_valid(name.ptr, name.len)) {
      const bool irrelevant = entry->kind == MS_PATH_DIRECTORY ? name.ptr[0] == '.'
                                                              : !(is_test_name(name) || (all && ms_span_ends_with_text(name, ".ms")));
      if (!irrelevant) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "discovered source path \"");
        ms_strbuild_append(&text, full);
        ms_strbuild_append_text(&text, "\" is not valid UTF-8; rename the file or directory using valid UTF-8");
        ms_project_error_message(scan->error, ms_message_take_builder(scan->arena, &text));
        ok = false;
      }
      continue;
    }
    ok = walk_entry(scan, scan_root, all, full, ms_arena_copy(scan->arena, name), entry->kind == MS_PATH_DIRECTORY);
  }
  ms_dir_entries_free(&entries);
  return ok;
}

static bool walk_entry(Scan *scan, MsSpan scan_root, bool all, MsSpan path, MsSpan name, bool is_dir) {
  if (!is_dir) {
    if ((all && ms_span_is_text(ms_path_ext(name), ".ms")) || is_test_name(name)) {
      ms_span_list_push(scan->files, path);
    }
    return true;
  }
  return !enters(scan, scan_root, all, path, name) || walk_children(scan, scan_root, all, path);
}

static bool scan_tree(Scan *scan, MsSpan root, bool all) {
  const MsPathKind kind = ms_path_kind(root);
  if (kind == MS_PATH_MISSING) {
    ms_project_error_path(scan->error, "lstat", root, errno == 0 ? 2 : errno);
    return false;
  }
  if (is_directory_link(root, kind)) {
    return true;
  }
  return walk_entry(scan, root, all, root, ms_path_file_name(root), kind == MS_PATH_DIRECTORY);
}

bool ms_project_discover(MsArena *arena, MsSpan root, MsSpan source, bool include_source, MsSpanList *files,
                         MsProjectError *error) {
  MsSpanList found = {0};
  Scan scan = {.arena = arena, .root = root, .source = source, .include_source = include_source,
               .files = &found, .error = error};
  const bool ok = (!include_source || scan_tree(&scan, source, true)) && scan_tree(&scan, root, false);
  ms_sort((uint8_t *)found.ptr, found.len, sizeof(MsSpan), ms_sort_compare_spans, NULL);
  for (size_t i = 0; ok && i < found.len; i++) {
    if (i == 0 || !ms_span_equal(found.ptr[i - 1], found.ptr[i])) {
      ms_span_list_push(files, found.ptr[i]);
    }
  }
  ms_span_list_free(&found);
  return ok;
}
