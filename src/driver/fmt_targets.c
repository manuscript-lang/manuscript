/* driver/fmt_targets.c: the files `ms fmt` formats, from its targets (crates/ms-cli/src/fmt.rs). */
#include "driver/fmt_targets.h"

#include "base/file.h"
#include "base/path.h"
#include "base/sort.h"
#include "compiler/project/project.h"

/* The text of `builder` copied into `arena`; the builder is freed. */
static MsSpan arena_text(MsArena *arena, MsStrBuild *builder) {
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(builder));
  ms_strbuild_free(builder);
  return text;
}

/* The canonical absolute spelling of `path`, or false. */
static bool physical(MsArena *arena, MsSpan path, MsSpan *out) {
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path)) {
    ms_strbuild_append(&joined, path);
  } else {
    MsString cwd = ms_string_empty();
    if (!ms_dir_current(&cwd)) {
      ms_strbuild_free(&joined);
      return false;
    }
    ms_path_append_joined(&joined, ms_string_span(&cwd), path);
    ms_string_release(&cwd);
  }
  MsString real = ms_string_empty();
  const bool ok = ms_file_real_path(ms_strbuild_span(&joined), &real);
  ms_strbuild_free(&joined);
  if (ok) {
    *out = ms_arena_copy(arena, ms_string_span(&real));
    ms_string_release(&real);
  }
  return ok;
}

/* `path` as shown: relative to the working directory when it lies below it, else absolute. */
static MsSpan display_of(MsArena *arena, MsSpan path) {
  MsSpan absolute = path;
  MsString cwd = ms_string_empty();
  MsSpan real_cwd = {0};
  if (!ms_dir_current(&cwd) || !physical(arena, ms_string_span(&cwd), &real_cwd)) {
    ms_string_release(&cwd);
    return path;
  }
  ms_string_release(&cwd);
  (void)physical(arena, path, &absolute);
  MsStrBuild relative = ms_strbuild_new();
  if (!ms_path_relative(&relative, real_cwd, absolute) || ms_path_escapes(ms_strbuild_span(&relative))) {
    ms_strbuild_free(&relative);
    return absolute;
  }
  if (relative.bytes.len > 0 && relative.bytes.ptr[0] == '-') {
    MsStrBuild dotted = ms_strbuild_new();
    ms_strbuild_append_text(&dotted, "./");
    ms_strbuild_append(&dotted, ms_strbuild_span(&relative));
    ms_strbuild_free(&relative);
    return arena_text(arena, &dotted);
  }
  return arena_text(arena, &relative);
}

static MsSpan path_message(MsArena *arena, const MsProjectError *error, MsSpan shown) {
  MsProjectError named = *error;
  named.path = shown;
  MsStrBuild text = ms_strbuild_new();
  if (error->os_error == 2) {
    ms_strbuild_append_text(&text, "file not found: ");
    ms_strbuild_append(&text, shown);
    ms_strbuild_append_text(&text, "; check the path and run from the directory that contains it");
    return arena_text(arena, &text);
  }
  ms_strbuild_free(&text);
  return ms_project_error_text(arena, &named);
}

static void add_problem(MsArena *arena, FmtProblemList *problems, MsSpan target, const MsProjectError *error) {
  FmtProblem problem = {.display = display_of(arena, target)};
  if (error->kind == MS_PERR_MANIFEST) {
    problem.manifest = true;
    problem.position = error->position;
    problem.message = error->message;
  } else if (error->kind == MS_PERR_PATH) {
    problem.display = display_of(arena, error->path);
    problem.message = path_message(arena, error, problem.display);
  } else {
    problem.message = ms_project_error_text(arena, error);
  }
  fmt_problem_list_push(problems, problem);
}

static int64_t file_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const FmtFile *x = (const void *)a;
  const FmtFile *y = (const void *)b;
  const size_t common = x->display.len < y->display.len ? x->display.len : y->display.len;
  for (size_t i = 0; i < common; i++) {
    if (x->display.ptr[i] != y->display.ptr[i]) {
      return x->display.ptr[i] < y->display.ptr[i] ? -1 : 1;
    }
  }
  return x->display.len == y->display.len ? 0 : (x->display.len < y->display.len ? -1 : 1);
}

static bool known(const FmtFileList *files, MsSpan path) {
  for (size_t i = 0; i < files->len; i++) {
    if (ms_span_equal(files->ptr[i].path, path)) {
      return true;
    }
  }
  return false;
}

static void add_files(MsArena *arena, const MsSpanList *paths, FmtFileList *files, FmtProblemList *problems) {
  for (size_t i = 0; i < paths->len; i++) {
    MsSpan canonical = {0};
    if (!physical(arena, paths->ptr[i], &canonical)) {
      MsProjectError error = {.kind = MS_PERR_PATH, .op = ms_span_of_text("lstat"), .path = paths->ptr[i], .os_error = 2};
      add_problem(arena, problems, paths->ptr[i], &error);
    } else if (!known(files, canonical)) {
      fmt_file_list_push(files, (FmtFile){.path = canonical, .display = display_of(arena, canonical)});
    }
  }
}

void fmt_resolve_targets(MsArena *arena, const MsSpan *targets, size_t count, FmtFileList *files,
                         FmtProblemList *problems) {
  for (size_t i = 0; i < count; i++) {
    MsSpanList paths = {0};
    MsProjectError error = {0};
    if (ms_project_format_files(arena, targets[i], &paths, &error)) {
      add_files(arena, &paths, files, problems);
    } else {
      add_problem(arena, problems, targets[i], &error);
    }
    ms_span_list_free(&paths);
  }
  ms_sort((uint8_t *)files->ptr, files->len, sizeof(FmtFile), file_order, NULL);
}
