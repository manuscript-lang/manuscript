/* cli/fmt_targets.c: the files `ms fmt` formats, from its targets (crates/ms-cli/src/fmt.rs). */
#include "cli/fmt_targets.h"

#include "base/file.h"
#include "base/path.h"
#include "base/sort.h"
#include "compiler/project/project.h"
#include "cli/display.h"

static void add_problem(MsArena *arena, FmtProblemList *problems, MsSpan target, const MsProjectError *error) {
  FmtProblem problem = {.display = ms_display_of(arena, target)};
  if (error->kind == MS_PERR_MANIFEST) {
    problem.manifest = true;
    problem.position = error->position;
    problem.message = error->message;
  } else if (error->kind == MS_PERR_PATH) {
    problem.display = ms_display_of(arena, error->path);
    problem.message = ms_display_path_message(arena, error, problem.display);
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
    if (!ms_display_physical(arena, paths->ptr[i], &canonical)) {
      MsProjectError error = {.kind = MS_PERR_PATH, .op = ms_span_of_text("lstat"), .path = paths->ptr[i], .os_error = 2};
      add_problem(arena, problems, paths->ptr[i], &error);
    } else if (!known(files, canonical)) {
      fmt_file_list_push(files, (FmtFile){.path = canonical, .display = ms_display_of(arena, canonical)});
    }
  }
}

static void add_target(MsArena *arena, MsSpan target, FmtFileList *files, FmtProblemList *problems) {
  MsSpanList paths = {0};
  MsProjectError error = {0};
  if (ms_project_format_files(arena, target, &paths, &error)) {
    add_files(arena, &paths, files, problems);
  } else {
    add_problem(arena, problems, target, &error);
  }
  ms_span_list_free(&paths);
}

void fmt_resolve_targets(MsArena *arena, const MsSpan *targets, size_t count, FmtFileList *files,
                         FmtProblemList *problems) {
  for (size_t i = 0; i < count; i++) {
    /* A workspace root without [project] stands for its members, as in the other commands. */
    MsSpanList members = {0};
    MsProjectError error = {0};
    bool root = false;
    if (!ms_project_workspace_members(arena, targets[i], &members, &root, &error)) {
      add_problem(arena, problems, targets[i], &error);
    } else if (!root) {
      add_target(arena, targets[i], files, problems);
    }
    for (size_t m = 0; root && m < members.len; m++) {
      add_target(arena, members.ptr[m], files, problems);
    }
    ms_span_list_free(&members);
  }
  ms_sort((uint8_t *)files->ptr, files->len, sizeof(FmtFile), file_order, NULL);
}
