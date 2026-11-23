/* Owns the selection of check inputs (check_selection.h). */
#include "cli/files.h"
#include "cli/check_selection.h"

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/sort.h"
#include "cli/display.h"

MS_LIST_DEFINE(PathList, path_list, MsSpan)

static int64_t order_inputs(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return ms_sort_compare_spans(NULL, (const uint8_t *)&((const CheckInput *)(const void *)a)->display,
                     (const uint8_t *)&((const CheckInput *)(const void *)b)->display);
}

static void report(MsArena *arena, CheckSelection *out, MsSpan path, MsSpan message) {
  check_problem_list_push(&out->problems, (CheckProblem){.display = ms_display_of(arena, path), .message = message});
}

/* Adds one target; in a collection it is made canonical and shown relative to the working directory. */
static void add_input(MsArena *arena, CheckSelection *out, MsSpan path) {
  if (!out->collection) {
    check_input_list_push(&out->inputs, (CheckInput){.path = path, .display = path});
    return;
  }
  MsSpan canonical = {0};
  if (!ms_display_physical(arena, path, &canonical)) {
    const MsSpan shown = ms_display_of(arena, path);
    report(arena, out, path,
           ms_message_format(arena, "file not found: %S; check the path and run from the directory that contains it",
                             shown));
    return;
  }
  if (ms_span_is_text(ms_path_file_name(path), "ms.toml")) {
    MsSpan parent = {0};
    if (ms_display_physical(arena, ms_path_parent(path), &parent)) {
      canonical = ms_cli_joined(arena, parent, ms_span_of_text("ms.toml"));
    }
  }
  for (size_t i = 0; i < out->inputs.len; i++) {
    if (ms_span_equal(out->inputs.ptr[i].path, canonical)) {
      return;
    }
  }
  check_input_list_push(&out->inputs, (CheckInput){.path = canonical, .display = ms_display_of(arena, canonical)});
}

/* ---- the .ms files below a directory ---- */

static bool selectable(MsArena *arena, MsSpan directory, const MsDirEntry *entry, bool *is_dir) {
  const MsSpan name = ms_string_span(&entry->name);
  *is_dir = entry->kind == MS_PATH_DIRECTORY;
  if (*is_dir) {
    return !ms_project_skips_name(name) &&
           ms_path_kind(ms_cli_joined(arena, ms_cli_joined(arena, directory, name), ms_span_of_text("ms.toml"))) == MS_PATH_MISSING;
  }
  const bool linked_directory = entry->kind == MS_PATH_SYMLINK && ms_dir_exists(ms_cli_joined(arena, directory, name));
  return !linked_directory && ms_span_ends_with(name, ms_span_of_text(".ms"));
}

typedef struct Walked {
  MsSpan name;
  bool is_dir;
} Walked;

static int64_t order_walked(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const Walked *x = (const Walked *)(const void *)a;
  const Walked *y = (const Walked *)(const void *)b;
  const int64_t by_name = ms_sort_compare_spans(NULL, (const uint8_t *)&x->name, (const uint8_t *)&y->name);
  return by_name != 0 ? by_name : (int64_t)x->is_dir - (int64_t)y->is_dir;
}

static bool walk(MsArena *arena, MsSpan directory, PathList *files, MsSpan *error) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(directory, &entries)) {
    *error = ms_message_format(arena, "open %S: cannot read the directory", directory);
    return false;
  }
  Walked *chosen = MS_ARENA_NEW_ARRAY(arena, Walked, entries.len + 1);
  size_t count = 0;
  for (size_t i = 0; i < entries.len; i++) {
    bool is_dir = false;
    if (selectable(arena, directory, &entries.ptr[i], &is_dir)) {
      chosen[count++] = (Walked){.name = ms_arena_copy(arena, ms_string_span(&entries.ptr[i].name)), .is_dir = is_dir};
    }
  }
  ms_dir_entries_free(&entries);
  ms_sort((uint8_t *)chosen, count, sizeof(Walked), order_walked, NULL);
  for (size_t i = 0; i < count; i++) {
    const MsSpan path = ms_cli_joined(arena, directory, chosen[i].name);
    if (!chosen[i].is_dir) {
      path_list_push(files, path);
    } else if (!walk(arena, path, files, error)) {
      return false;
    }
  }
  return true;
}

static void add_directory(MsArena *arena, CheckSelection *out, MsSpan target) {
  out->collection = true;
  MsSpan root = {0};
  if (!ms_display_physical(arena, target, &root)) {
    report(arena, out, target,
           ms_message_format(arena, "file not found: %S; check the path and run from the directory that contains it",
                             ms_display_of(arena, target)));
    return;
  }
  PathList files = {0};
  MsSpan error = {0};
  if (!walk(arena, root, &files, &error)) {
    report(arena, out, target, error);
  }
  for (size_t i = 0; i < files.len; i++) {
    add_input(arena, out, files.ptr[i]);
  }
  path_list_free(&files);
}

void check_select_inputs(MsArena *arena, const MsSpan *targets, size_t count, CheckSelection *out) {
  *out = (CheckSelection){.collection = count > 1};
  for (size_t i = 0; i < count; i++) {
    if (!ms_dir_exists(targets[i])) {
      add_input(arena, out, targets[i]);
      continue;
    }
    const MsSpan manifest = ms_cli_joined(arena, targets[i], ms_span_of_text("ms.toml"));
    if (ms_path_kind(manifest) != MS_PATH_MISSING) {
      add_input(arena, out, manifest);
    } else {
      add_directory(arena, out, targets[i]);
    }
  }
  ms_sort((uint8_t *)out->inputs.ptr, out->inputs.len, sizeof(CheckInput), order_inputs, NULL);
}

void check_selection_free(CheckSelection *selection) {
  check_input_list_free(&selection->inputs);
  check_problem_list_free(&selection->problems);
}
