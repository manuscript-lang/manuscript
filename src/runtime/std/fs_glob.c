/* `glob_entries` of @std/fs: the paths under a root that match any of a list of patterns and none of the exclusions,
 * sorted by path. Patterns are compiled by the @std/path matcher (path.h). It runs on the runtime thread because the
 * exclusion filter is program code. Everything it owns is in one GlobWalk, which a cleanup frees if the filter leaves by
 * a jump. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdlib.h>

#include "base/alloc.h"
#include "runtime/core/fault_abi.h"
#include "runtime/std/fs_tree.h"
#include "runtime/std/path.h"

enum { GLOB_MAX_DEPTH = 1024 };

/* A compiled pattern with what is needed to apply it. */
typedef struct Pattern {
  MsObj *glob;           /* owned: the compiled matcher */
  bool directories_only; /* the pattern ended in `/`: only directories, and links to them, match */
  bool absolute;         /* the pattern starts with `/`: matched against the absolute path */
} Pattern;

MS_LIST_DEFINE(PatternList, pattern_list, Pattern)

/* One match. */
typedef struct Found {
  MsString path;
  MsString name;
  bool directory;
  bool symlink;
  size_t order; /* the order of discovery, which keeps the first of equal paths */
} Found;

MS_LIST_DEFINE(FoundList, found_list, Found)
MS_LIST_DEFINE(StartList, start_list, MsSpan)

typedef struct GlobWalk {
  MsFail fail;
  bool follow_links;
  int64_t remaining; /* entries the walk may still visit */
  int64_t max_results;
  MsFsClosure *filter;
  PatternList patterns;
  PatternList excluded;
  MsStrBuild root;      /* the absolute root every matched path is relative to */
  MsStrBuild ancestors; /* the canonical directories being walked, as names */
  FoundList found;
  MsFsArguments arguments;
  MsString relative_value; /* the two texts a visit matches against */
  MsString absolute_value;
  bool values_live;
} GlobWalk;

static void patterns_free(PatternList *patterns) {
  for (size_t i = 0; i < patterns->len; i++) {
    patterns->ptr[i].glob->drop(patterns->ptr[i].glob);
  }
  pattern_list_free(patterns);
}

static void values_free(GlobWalk *walk) {
  if (walk->values_live) {
    ms_string_release(&walk->relative_value);
    ms_string_release(&walk->absolute_value);
    walk->values_live = false;
  }
}

static void found_free(FoundList *found) {
  for (size_t i = 0; i < found->len; i++) {
    ms_string_release(&found->ptr[i].path);
    ms_string_release(&found->ptr[i].name);
  }
  found_list_free(found);
}

static void walk_free(GlobWalk *walk) {
  ms_fail_free(&walk->fail);
  patterns_free(&walk->patterns);
  patterns_free(&walk->excluded);
  ms_strbuild_free(&walk->root);
  ms_strbuild_free(&walk->ancestors);
  found_free(&walk->found);
  ms_fs_arguments_free(&walk->arguments);
  values_free(walk);
}

static bool fail_status(GlobWalk *walk, uint8_t status) {
  ms_fail_status(&walk->fail, status);
  return false;
}

static bool fail_at(GlobWalk *walk, int code, const char *operation, MsSpan path) {
  ms_fail_uv(&walk->fail, code, operation, path);
  return false;
}

/* The canonical form of an existing path, appended to `out`. */
static int canonical_bytes(MsSpan path, MsStrBuild *out) {
  MsOsText text = ms_os_text_new(path);
  const int code = ms_fs_realpath(text.ptr, out);
  ms_os_text_free(&text);
  return code;
}

/* ---- compiling patterns ---- */

/* `text` without its `.` and empty segments, so `./a`, `a/./b` and `a//b` match as the cleaned path does. A leading `/`
 * stays; `..` segments stay. */
static void without_dot_segments(MsSpan text, MsStrBuild *out) {
  if (text.len > 0 && text.ptr[0] == '/') {
    ms_strbuild_append_byte(out, '/');
  }
  bool first = true;
  size_t start = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i < text.len && text.ptr[i] != '/') {
      continue;
    }
    const size_t length = i - start;
    const bool skipped = length == 0 || (length == 1 && text.ptr[start] == '.');
    if (!skipped) {
      if (!first) {
        ms_strbuild_append_byte(out, '/');
      }
      ms_strbuild_append(out, ms_span_of(text.ptr + start, length));
      first = false;
    }
    start = i + 1;
  }
}

/* Compiles the cleaned pattern; false with `walk->fail` set (an unusable pattern is invalid input). */
static bool compile_one(GlobWalk *walk, MsSpan pattern, Pattern *out) {
  if (!ms_fs_text_ok(pattern)) {
    return fail_status(walk, MS_STATUS_INVALID_INPUT);
  }
  MsStrBuild cleaned = ms_strbuild_new();
  without_dot_segments(pattern, &cleaned);
  MsString value = ms_strbuild_finish(&cleaned);
  ms_strbuild_free(&cleaned);
  MsObj *glob = NULL;
  const uint8_t status = msstd_path_compile_glob(0, &value, &glob);
  ms_string_release(&value);
  if (status != MS_STATUS_OK) {
    return fail_status(walk, MS_STATUS_INVALID_INPUT);
  }
  out->glob = glob;
  out->directories_only = pattern.len > 0 && pattern.ptr[pattern.len - 1] == '/';
  out->absolute = pattern.len > 0 && pattern.ptr[0] == '/';
  return true;
}

static bool compile_list(GlobWalk *walk, const MsList *list, PatternList *out) {
  const MsString *items = (const MsString *)(const void *)list->ptr;
  for (size_t i = 0; i < list->len; i++) {
    Pattern pattern = {0};
    if (!compile_one(walk, ms_string_span(&items[i]), &pattern)) {
      return false;
    }
    pattern_list_push(out, pattern);
  }
  return true;
}

/* ---- the texts of one visit ---- */

/* Whether `pattern` matches the text it applies to; false on a matcher failure, which is set in `walk`. */
static bool pattern_hit(GlobWalk *walk, const Pattern *pattern, bool names_directory, bool *hit) {
  *hit = false;
  if (pattern->directories_only && !names_directory) {
    return true;
  }
  uint8_t matched = 0;
  const MsString *value = pattern->absolute ? &walk->absolute_value : &walk->relative_value;
  if (msstd_path_glob_matches(pattern->glob, value, &matched) != MS_STATUS_OK) {
    return fail_status(walk, MS_STATUS_FAILED);
  }
  *hit = matched != 0;
  return true;
}

/* Whether any of `patterns` applies; `skip_relative` leaves out the relative ones (the root is not an entry inside
 * itself, so `.*` must not list it). */
static bool any_hit(GlobWalk *walk, const PatternList *patterns, bool names_directory, bool skip_relative, bool *hit) {
  *hit = false;
  for (size_t i = 0; i < patterns->len && !*hit; i++) {
    if (skip_relative && !patterns->ptr[i].absolute) {
      continue;
    }
    if (!pattern_hit(walk, &patterns->ptr[i], names_directory, hit)) {
      return false;
    }
  }
  return true;
}

/* ---- paths relative to the root ---- */

/* The next element of a cleaned path; an absolute path's root is an element of its own ("/"). */
static bool next_element(MsSpan path, size_t *cursor, MsSpan *element) {
  if (*cursor == 0 && path.len > 0 && ms_path_is_separator(path.ptr[0])) {
    *cursor = 1;
    *element = ms_span_of(path.ptr, 1);
    return true;
  }
  while (*cursor < path.len) {
    while (*cursor < path.len && ms_path_is_separator(path.ptr[*cursor])) {
      *cursor += 1;
    }
    const size_t start = *cursor;
    while (*cursor < path.len && !ms_path_is_separator(path.ptr[*cursor])) {
      *cursor += 1;
    }
    const size_t length = *cursor - start;
    if (length > 0 && !(length == 1 && path.ptr[start] == '.')) {
      *element = ms_span_of(path.ptr + start, length);
      return true;
    }
  }
  return false;
}

static bool elements_equal(MsSpan a, MsSpan b) {
  if (a.len == 1 && b.len == 1 && ms_path_is_separator(a.ptr[0]) && ms_path_is_separator(b.ptr[0])) {
    return true;
  }
  return ms_span_equal(a, b);
}

static void append_element(MsStrBuild *out, MsSpan element) {
  if (ms_strbuild_length(out) > 0) {
    ms_strbuild_append_byte(out, '/');
  }
  ms_strbuild_append(out, element);
}

/* `filepath.Rel(root, p)` for a `p` at or under `root`, or reached through `..` patterns, with `/` between the elements
 * on every host. */
static void relative_path(MsSpan root, MsSpan path, MsStrBuild *out) {
  MsStrBuild clean_root = ms_strbuild_new();
  MsStrBuild clean_path = ms_strbuild_new();
  ms_path_clean(&clean_root, root);
  ms_path_clean(&clean_path, path);
  const MsSpan from = ms_strbuild_span(&clean_root);
  const MsSpan to = ms_strbuild_span(&clean_path);
  size_t from_cursor = 0;
  size_t to_cursor = 0;
  MsSpan left = ms_span_of(NULL, 0);
  MsSpan right = ms_span_of(NULL, 0);
  bool have_left = next_element(from, &from_cursor, &left);
  bool have_right = next_element(to, &to_cursor, &right);
  while (have_left && have_right && elements_equal(left, right)) {
    have_left = next_element(from, &from_cursor, &left);
    have_right = next_element(to, &to_cursor, &right);
  }
  while (have_left) {
    append_element(out, ms_span_of_text(".."));
    have_left = next_element(from, &from_cursor, &left);
  }
  while (have_right) {
    append_element(out, right);
    have_right = next_element(to, &to_cursor, &right);
  }
  if (ms_strbuild_length(out) == 0) {
    ms_strbuild_append_byte(out, '.');
  }
  ms_strbuild_free(&clean_root);
  ms_strbuild_free(&clean_path);
}

/* ---- results ---- */

static bool found_add(GlobWalk *walk, MsSpan path, MsSpan name, bool directory, bool symlink) {
  if ((int64_t)walk->found.len >= walk->max_results) {
    return fail_status(walk, MS_STATUS_LIMIT_EXCEEDED);
  }
  found_list_push(&walk->found, (Found){.path = ms_string_from_span(path),
                                        .name = ms_string_from_span(name),
                                        .directory = directory,
                                        .symlink = symlink,
                                        .order = walk->found.len});
  return true;
}

/* ---- visiting ---- */

/* What a visit needs to know about one path. */
typedef struct Visit {
  MsStrBuild relative; /* the portable relative path, lossy UTF-8 */
  MsStrBuild name;     /* the last element, lossy UTF-8 */
  MsStrBuild absolute; /* the path, lossy UTF-8 */
  bool directory;
  bool symlink;
} Visit;

static void visit_free(Visit *visit) {
  ms_strbuild_free(&visit->relative);
  ms_strbuild_free(&visit->name);
  ms_strbuild_free(&visit->absolute);
}

static void visit_fill(GlobWalk *walk, MsSpan path, const uv_stat_t *info, Visit *visit) {
  MsStrBuild raw = ms_strbuild_new();
  relative_path(ms_strbuild_span(&walk->root), path, &raw);
  ms_fs_append_lossy(&visit->relative, ms_strbuild_span(&raw));
  ms_fs_append_lossy(&visit->name, ms_path_base(path));
  ms_fs_append_lossy(&visit->absolute, path);
  ms_strbuild_free(&raw);
  visit->directory = ms_fs_is_directory(info);
  visit->symlink = ms_fs_is_link(info);
}

/* A link to a directory counts as one for a pattern that ends in `/`. */
static bool names_directory(const Visit *visit, MsSpan path) {
  if (visit->directory) {
    return true;
  }
  uv_stat_t target;
  return visit->symlink && ms_fs_stat_bytes(path, true, &target) == 0 && ms_fs_is_directory(&target);
}

/* Matches the visit against the exclusions and the patterns; `*excluded` and `*selected` are the answers. */
static bool classify(GlobWalk *walk, const Visit *visit, MsSpan path, bool *excluded, bool *selected) {
  walk->relative_value = ms_string_from_span(ms_strbuild_span(&visit->relative));
  walk->absolute_value = ms_string_from_span(ms_strbuild_span(&visit->absolute));
  walk->values_live = true;
  const bool directory = names_directory(visit, path);
  bool ok = any_hit(walk, &walk->excluded, directory, false, excluded);
  *selected = false;
  if (ok && !*excluded) {
    const bool is_root = ms_span_is_text(ms_strbuild_span(&visit->relative), ".");
    ok = any_hit(walk, &walk->patterns, directory, is_root, selected);
  }
  values_free(walk);
  return ok;
}

/* Asks the exclusion filter about an entry; true to leave it out. */
static bool filter_excludes(GlobWalk *walk, const Visit *visit) {
  if (walk->filter == NULL) {
    return false;
  }
  ms_fs_arguments_set(&walk->arguments, ms_strbuild_span(&visit->relative), ms_strbuild_span(&visit->name));
  const MsFsArguments *arguments = &walk->arguments;
  const uint8_t excluded =
      walk->filter->code.entry(walk->filter, arguments->first.low_bits, arguments->first.tagged,
                               arguments->second.low_bits, arguments->second.tagged, visit->directory ? 1 : 0,
                               visit->symlink ? 1 : 0);
  ms_fs_arguments_free(&walk->arguments);
  return excluded != 0;
}

static bool visit_path(GlobWalk *walk, MsSpan path, size_t depth);

/* Visits every child of the directory `path`. */
static bool visit_children(GlobWalk *walk, MsSpan path, size_t depth) {
  MsStrBuild names = ms_strbuild_new();
  bool ok = ms_fs_names_read(path, &names, &walk->fail);
  size_t cursor = 0;
  MsSpan name;
  while (ok && ms_fs_names_next(ms_strbuild_span(&names), &cursor, &name)) {
    MsStrBuild child = ms_strbuild_new();
    ms_path_join(path, name, &child);
    ok = visit_path(walk, ms_strbuild_span(&child), depth + 1);
    ms_strbuild_free(&child);
  }
  ms_strbuild_free(&names);
  return ok;
}

/* Enters the directory `path` unless it is one already being walked (a link back up). */
static bool enter_directory(GlobWalk *walk, MsSpan path, size_t depth) {
  MsStrBuild canonical = ms_strbuild_new();
  const int code = canonical_bytes(path, &canonical);
  if (code != 0) {
    ms_strbuild_free(&canonical);
    return fail_at(walk, code, "lstat", path);
  }
  if (ms_fs_names_contain(&walk->ancestors, ms_strbuild_span(&canonical))) {
    ms_strbuild_free(&canonical);
    return true;
  }
  const size_t mark = ms_strbuild_length(&walk->ancestors);
  ms_fs_names_push(&walk->ancestors, ms_strbuild_span(&canonical));
  ms_strbuild_free(&canonical);
  const bool ok = visit_children(walk, path, depth);
  walk->ancestors.bytes.len = mark;
  return ok;
}

/* Whether the entry is a directory to enter, following a link when asked; false without a failure for a dangling or
 * looping link. */
static bool enterable(GlobWalk *walk, MsSpan path, uv_stat_t *info, bool *enter) {
  *enter = false;
  if (ms_fs_is_link(info) && walk->follow_links) {
    const int code = ms_fs_stat_bytes(path, true, info);
    if (code == UV_ENOENT || code == UV_ELOOP) {
      return true;
    }
    if (code != 0) {
      return fail_at(walk, code, "stat", path);
    }
  }
  *enter = ms_fs_is_directory(info);
  return true;
}

static bool visit_path(GlobWalk *walk, MsSpan path, size_t depth) {
  if (ms_fail_poll_cancel(&walk->fail)) {
    return false;
  }
  if (walk->remaining == 0 || depth > GLOB_MAX_DEPTH) {
    return fail_status(walk, MS_STATUS_LIMIT_EXCEEDED);
  }
  walk->remaining -= 1;
  uv_stat_t info;
  const int code = ms_fs_stat_bytes(path, false, &info);
  if (code != 0) {
    return fail_at(walk, code, "lstat", path);
  }
  Visit visit = {.relative = ms_strbuild_new(), .name = ms_strbuild_new(), .absolute = ms_strbuild_new()};
  bool excluded = false;
  bool selected = false;
  visit_fill(walk, path, &info, &visit);
  bool ok = classify(walk, &visit, path, &excluded, &selected);
  if (ok && !excluded) {
    excluded = filter_excludes(walk, &visit);
  }
  // The key is the path, so a path that is already there is kept as it was.
  if (ok && !excluded && selected) {
    ok = found_add(walk, ms_strbuild_span(&visit.relative), ms_strbuild_span(&visit.name), visit.directory,
                   visit.symlink);
  }
  visit_free(&visit);
  if (!ok || excluded) {
    return ok;
  }
  bool enter = false;
  return enterable(walk, path, &info, &enter) && (!enter || enter_directory(walk, path, depth));
}

/* ---- where the walk starts ---- */

static bool has_glob_character(MsSpan part) {
  static const uint8_t special[] = {'*', '?', '[', ']', '{', '}', '(', ')', '!'};
  for (size_t i = 0; i < part.len; i++) {
    for (size_t j = 0; j < sizeof special; j++) {
      if (part.ptr[i] == special[j]) {
        return true;
      }
    }
  }
  return false;
}

/* The directory a pattern's literal prefix leads to: `a/b/ then a star-suffix` starts at `a/b`, a leading `..` climbs. */
static void pattern_base(GlobWalk *walk, MsSpan pattern, MsStrBuild *base) {
  ms_strbuild_append(base, ms_strbuild_span(&walk->root));
  size_t start = 0;
  if (ms_path_is_absolute(pattern)) {
    ms_strbuild_clear(base);
    ms_strbuild_append_byte(base, '/');
    while (start < pattern.len && pattern.ptr[start] == '/') {
      start += 1;
    }
  }
  for (size_t i = start; i <= pattern.len; i++) {
    if (i < pattern.len && pattern.ptr[i] != '/') {
      continue;
    }
    const MsSpan part = ms_span_of(pattern.ptr + start, i - start);
    start = i + 1;
    if (part.len == 0 || ms_span_is_text(part, ".")) {
      continue;
    }
    if (has_glob_character(part)) {
      break;
    }
    MsStrBuild next = ms_strbuild_new();
    if (ms_span_is_text(part, "..")) {
      ms_path_dir(ms_strbuild_span(base), &next);
    } else {
      ms_path_join(ms_strbuild_span(base), part, &next);
    }
    ms_strbuild_free(base);
    *base = next;
  }
}

/* The directories to start from, packed as names: the root, and where each pattern's literal prefix leads. */
static void collect_starts(GlobWalk *walk, const MsList *patterns, MsStrBuild *starts) {
  ms_fs_names_push(starts, ms_strbuild_span(&walk->root));
  const MsString *items = (const MsString *)(const void *)patterns->ptr;
  for (size_t i = 0; i < patterns->len; i++) {
    MsStrBuild base = ms_strbuild_new();
    pattern_base(walk, ms_string_span(&items[i]), &base);
    uv_stat_t info;
    const bool directory = ms_fs_stat_bytes(ms_strbuild_span(&base), false, &info) == 0 && ms_fs_is_directory(&info);
    if (directory) {
      ms_fs_names_push(starts, ms_strbuild_span(&base));
    } else if (!ms_span_equal(ms_strbuild_span(&base), ms_strbuild_span(&walk->root))) {
      MsStrBuild parent = ms_strbuild_new();
      ms_path_dir(ms_strbuild_span(&base), &parent);
      ms_fs_names_push(starts, ms_strbuild_span(&parent));
      ms_strbuild_free(&parent);
    }
    ms_strbuild_free(&base);
  }
}

/* Orders starts by length, then bytes. */
static int compare_starts(const void *left, const void *right) {
  const MsSpan *a = left;
  const MsSpan *b = right;
  if (a->len != b->len) {
    return a->len < b->len ? -1 : 1;
  }
  for (size_t i = 0; i < a->len; i++) {
    if (a->ptr[i] != b->ptr[i]) {
      return a->ptr[i] < b->ptr[i] ? -1 : 1;
    }
  }
  return 0;
}

/* The starts without duplicates and without any inside another, shortest first, as views into `starts`. */
static void select_starts(const MsStrBuild *starts, StartList *out) {
  StartList all = {0};
  size_t cursor = 0;
  MsSpan name;
  while (ms_fs_names_next(ms_strbuild_span(starts), &cursor, &name)) {
    start_list_push(&all, name);
  }
  if (all.len > 0) {
    qsort(all.ptr, all.len, sizeof(MsSpan), compare_starts);
  }
  for (size_t i = 0; i < all.len; i++) {
    bool inside = false;
    for (size_t j = 0; j < out->len && !inside; j++) {
      inside = ms_fs_within_path(out->ptr[j], all.ptr[i]);
    }
    if (!inside) {
      start_list_push(out, all.ptr[i]);
    }
  }
  start_list_free(&all);
}

/* Walks from each selected start; a start that is gone is skipped. */
static bool walk_starts(GlobWalk *walk, const MsList *patterns) {
  MsStrBuild starts = ms_strbuild_new();
  StartList selected = {0};
  collect_starts(walk, patterns, &starts);
  select_starts(&starts, &selected);
  bool ok = true;
  for (size_t i = 0; ok && i < selected.len; i++) {
    ok = visit_path(walk, selected.ptr[i], 0);
    if (!ok && walk->fail.status == MS_STATUS_NOT_FOUND) {
      ms_fail_free(&walk->fail);
      walk->fail = ms_fail_new();
      ok = true;
    }
  }
  start_list_free(&selected);
  ms_strbuild_free(&starts);
  return ok;
}

/* ---- the result ---- */

static int compare_found(const void *left, const void *right) {
  const Found *a = left;
  const Found *b = right;
  const int order = ms_string_compare(&a->path, &b->path);
  if (order != 0) {
    return order;
  }
  if (a->order == b->order) {
    return 0;
  }
  return a->order < b->order ? -1 : 1;
}

/* Sorts what was found and writes it as a list, leaving out a path found again. */
static void write_found(GlobWalk *walk, MsList *out) {
  if (walk->found.len > 1) {
    qsort(walk->found.ptr, walk->found.len, sizeof(Found), compare_found);
  }
  ms_list_reserve(out, sizeof(MsFsPathEntry), walk->found.len);
  for (size_t i = 0; i < walk->found.len; i++) {
    Found *item = &walk->found.ptr[i];
    const bool repeated = i > 0 && ms_string_equal(&walk->found.ptr[i - 1].path, &item->path);
    if (repeated) {
      continue;
    }
    const MsFsPathEntry entry = {.path = ms_string_clone(&item->path),
                                 .name = ms_string_clone(&item->name),
                                 .directory = item->directory ? 1 : 0,
                                 .symlink = item->symlink ? 1 : 0};
    ms_list_push(out, sizeof entry, &entry);
  }
}

/* ---- the native ---- */

static bool prepare(GlobWalk *walk, MsSpan path, const MsList *patterns, const MsList *exclude) {
  if (!compile_list(walk, patterns, &walk->patterns) || !compile_list(walk, exclude, &walk->excluded)) {
    return false;
  }
  if (path.len == 0) {
    return fail_status(walk, MS_STATUS_INVALID_INPUT);
  }
  // Keep every traversal start in the same coordinates, including `.` and parent patterns.
  ms_fs_absolute(path, &walk->root);
  return true;
}

uint8_t msstd_fs_glob_entries(const MsString *path, const MsList *patterns, const MsList *exclude, uint8_t follow_links,
                              uint8_t has_max_entries, int64_t max_entries, uint8_t has_max_results,
                              int64_t max_results, MsObj *filter, MsList *out, MsString *err) {
  GlobWalk walk = {.follow_links = follow_links != 0,
                   .filter = (MsFsClosure *)filter,
                   .fail = ms_fail_new(),
                   .root = ms_strbuild_new(),
                   .ancestors = ms_strbuild_new()};
  const MsSpan given = ms_string_span(path);
  if (!ms_fs_limit(has_max_entries, max_entries, &walk.remaining) ||
      !ms_fs_limit(has_max_results, max_results, &walk.max_results)) {
    ms_fail_status(&walk.fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish_at(&walk.fail, given, err);
  }
  if (prepare(&walk, given, patterns, exclude)) {
    (void)walk_starts(&walk, patterns);
  }
  if (!ms_fail_failed(&walk.fail)) {
    write_found(&walk, out);
  }
  MsFail fail = walk.fail; /* a stop request unwinds out of the finish, so the walk is freed before it */
  walk.fail = ms_fail_new();
  walk_free(&walk);
  return ms_fail_finish_at(&fail, given, err);
}
