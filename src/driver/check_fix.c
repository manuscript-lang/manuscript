/* Owns applying the fixes of check_fix.h. */
#include "driver/check_fix.h"

#include "base/alloc.h"
#include "base/bytes.h"
#include "base/file.h"
#include "base/hash.h"
#include "base/message.h"
#include "base/sort.h"

static int64_t order_fixes(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const CheckFix *x = (const CheckFix *)(const void *)a;
  const CheckFix *y = (const CheckFix *)(const void *)b;
  const size_t common = x->path.len < y->path.len ? x->path.len : y->path.len;
  const int by_path = common == 0 ? 0 : __builtin_memcmp(x->path.ptr, y->path.ptr, common);
  if (by_path != 0) {
    return by_path < 0 ? -1 : 1;
  }
  if (x->path.len != y->path.len) {
    return x->path.len < y->path.len ? -1 : 1;
  }
  if (x->start != y->start) {
    return x->start < y->start ? -1 : 1;
  }
  if (x->end != y->end) {
    return x->end < y->end ? -1 : 1;
  }
  const size_t n = x->replacement.len < y->replacement.len ? x->replacement.len : y->replacement.len;
  const int text = n == 0 ? 0 : __builtin_memcmp(x->replacement.ptr, y->replacement.ptr, n);
  if (text != 0) {
    return text < 0 ? -1 : 1;
  }
  return x->replacement.len == y->replacement.len ? 0 : (x->replacement.len < y->replacement.len ? -1 : 1);
}

static bool equal_fix(const CheckFix *a, const CheckFix *b) {
  return ms_span_equal(a->path, b->path) && a->start == b->start && a->end == b->end &&
         ms_span_equal(a->replacement, b->replacement);
}

static bool failed_path(const CheckFixRun *run, MsSpan path) {
  for (size_t i = 0; i < run->problems.len; i++) {
    if (ms_span_equal(run->problems.ptr[i].path, path)) {
      return true;
    }
  }
  return false;
}

/* Whether this text of the file was seen; records it either way. */
static bool seen_before(CheckFixRun *run, MsSpan path, MsSpan text) {
  const uint64_t hash = ms_hash_span(text);
  for (size_t i = 0; i < run->seen_count; i++) {
    if (run->seen_hash[i] == hash && ms_span_equal(run->seen_path[i], path)) {
      return true;
    }
  }
  if (run->seen_count == run->seen_capacity) {
    const size_t capacity = run->seen_capacity == 0 ? 16 : run->seen_capacity * 2;
    uint64_t *hashes = ms_alloc(capacity * sizeof(uint64_t));
    MsSpan *paths = ms_alloc(capacity * sizeof(MsSpan));
    for (size_t i = 0; i < run->seen_count; i++) {
      hashes[i] = run->seen_hash[i];
      paths[i] = run->seen_path[i];
    }
    ms_free(run->seen_hash);
    ms_free(run->seen_path);
    run->seen_hash = hashes;
    run->seen_path = paths;
    run->seen_capacity = capacity;
  }
  run->seen_hash[run->seen_count] = hash;
  run->seen_path[run->seen_count++] = path;
  return false;
}

static void add_problem(MsArena *arena, CheckFixRun *run, MsSpan path, MsSpan message) {
  check_fix_problem_list_push(&run->problems, (CheckFixProblem){.path = path, .message = message});
  (void)arena;
}

/* The fixes of one file that do not overlap, in order; returns how many and marks them in `chosen`. */
static size_t choose(const CheckFix *fixes, size_t count, size_t length, bool *chosen) {
  size_t picked = 0;
  uint32_t last_end = 0;
  for (size_t i = 0; i < count; i++) {
    const bool valid = fixes[i].start <= fixes[i].end && fixes[i].end <= length;
    if (valid && (picked == 0 || fixes[i].start >= last_end)) {
      last_end = fixes[i].end;
      chosen[i] = true;
      picked++;
    }
  }
  return picked;
}

static MsSpan edited_text(MsArena *arena, MsSpan text, const CheckFix *fixes, const bool *chosen, size_t count) {
  MsStrBuild out = ms_strbuild_new();
  size_t at = 0;
  for (size_t i = 0; i < count; i++) {
    if (!chosen[i]) {
      continue;
    }
    ms_strbuild_append(&out, ms_span_of(text.ptr + at, fixes[i].start - at));
    ms_strbuild_append(&out, fixes[i].replacement);
    at = fixes[i].end;
  }
  ms_strbuild_append(&out, ms_span_of(text.ptr + at, text.len - at));
  const MsSpan result = ms_message_from_builder(arena, &out);
  ms_strbuild_free(&out);
  return result;
}

static bool note_edited(CheckFixRun *run, MsSpan path) {
  for (size_t i = 0; i < run->edited_count; i++) {
    if (ms_span_equal(run->edited[i], path)) {
      return false;
    }
  }
  MsSpan *grown = ms_alloc((run->edited_count + 1) * sizeof(MsSpan));
  for (size_t i = 0; i < run->edited_count; i++) {
    grown[i] = run->edited[i];
  }
  grown[run->edited_count++] = path;
  ms_free(run->edited);
  run->edited = grown;
  return true;
}

/* Applies the fixes of one file (`fixes[0..count)`, sorted and distinct). Returns how many were applied. */
static size_t fix_file(MsArena *arena, CheckFixRun *run, const CheckFix *fixes, size_t count) {
  const MsSpan path = fixes[0].path;
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    add_problem(arena, run, path,
                ms_message_format(arena, "cannot read source for --fix: cannot open it; check the file and its "
                                         "permissions, then re-run the command"));
    return 0;
  }
  const MsSpan text = ms_arena_copy(arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  bool *chosen = MS_ARENA_NEW_ARRAY(arena, bool, count);
  const size_t picked = choose(fixes, count, text.len, chosen);
  if (picked == 0) {
    return 0;
  }
  (void)seen_before(run, path, text);
  const MsSpan result = edited_text(arena, text, fixes, chosen, count);
  if (seen_before(run, path, result)) {
    add_problem(arena, run, path,
                ms_span_of_text("--fix would return this file to an earlier state because two fixes undo each "
                                "other; leaving it as it is, so report the pair as a bug and apply one of them by "
                                "hand"));
    return 0;
  }
  if (!ms_file_write(path, result)) {
    add_problem(arena, run, path,
                ms_message_format(arena, "cannot write source for --fix: cannot write it; check the file and its "
                                         "permissions, then re-run the command"));
    return 0;
  }
  (void)note_edited(run, path);
  return picked;
}

size_t check_apply_fixes(MsArena *arena, CheckFixRun *run, CheckFixList *fixes) {
  ms_sort((uint8_t *)fixes->ptr, fixes->len, sizeof(CheckFix), order_fixes, NULL);
  size_t applied = 0;
  size_t start = 0;
  while (start < fixes->len) {
    size_t end = start;
    size_t distinct = 0;
    CheckFix *file = fixes->ptr + start;
    while (end < fixes->len && ms_span_equal(fixes->ptr[end].path, file[0].path)) {
      if (end == start || !equal_fix(&fixes->ptr[end], &fixes->ptr[end - 1])) {
        fixes->ptr[start + distinct++] = fixes->ptr[end];
      }
      end++;
    }
    if (!failed_path(run, file[0].path)) {
      applied += fix_file(arena, run, file, distinct);
    }
    start = end;
  }
  run->fixes += applied;
  return applied;
}

void check_fix_run_free(CheckFixRun *run) {
  check_fix_problem_list_free(&run->problems);
  ms_free(run->edited);
  ms_free(run->seen_hash);
  ms_free(run->seen_path);
  *run = (CheckFixRun){0};
}
