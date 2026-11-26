/* cli/review_command.c: `ms map --view review`. */
#include "cli/files.h"
#include "cli/review_command.h"

#include <stdio.h>

#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "tooling/diff.h"
#include "tooling/review.h"
#include "tooling/checked_input.h"
#include "cli/invocation.h"
#include "tooling/facts.h"
#include "tooling/report.h"

enum { STATUS_FAILED = 1 };

static bool path_exists(MsSpan path) {
  return ms_file_is_regular(path) || ms_dir_exists(path);
}

static MsSpan path_dir(MsArena *arena, MsSpan path) {
  MsStrBuild out = ms_strbuild_new();
  ms_path_dir(path, &out);
  const MsSpan text = ms_message_take_builder(arena, &out);
  return text;
}

static MsSpan path_join(MsArena *arena, MsSpan left, MsSpan right) {
  MsStrBuild out = ms_strbuild_new();
  ms_path_join(left, right, &out);
  const MsSpan text = ms_message_take_builder(arena, &out);
  return text;
}

/* The diff's repository-relative path at or above the project root; the project may sit below the checkout root. */
static MsSpan locate_diff_path(MsArena *arena, MsSpan root, MsSpan path, bool deleted) {
  MsSpan dir = root;
  for (;;) {
    const MsSpan candidate = path_join(arena, dir, path);
    if (path_exists(deleted ? path_dir(arena, candidate) : candidate)) {
      return candidate;
    }
    const MsSpan parent = path_dir(arena, dir);
    if (ms_span_equal(parent, dir)) {
      return path_join(arena, root, path);
    }
    dir = parent;
  }
}

typedef struct OverlayList {
  MsOverlayFile *ptr;
  size_t len, cap;
} OverlayList;

static void overlay_push(MsArena *arena, OverlayList *list, MsOverlayFile file) {
  if (list->len == list->cap) {
    const size_t cap = list->cap == 0 ? 4 : list->cap * 2;
    MsOverlayFile *grown = MS_ARENA_NEW_ARRAY(arena, MsOverlayFile, cap);
    for (size_t i = 0; i < list->len; i++) {
      grown[i] = list->ptr[i];
    }
    list->ptr = grown;
    list->cap = cap;
  }
  list->ptr[list->len++] = file;
}

static bool read_text(MsArena *arena, MsSpan path, MsSpan *out) {
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    return false;
  }
  *out = ms_arena_copy(arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  return true;
}

static bool read_stdin(MsArena *arena, MsSpan *out) {
  MsStrBuild all = ms_strbuild_new();
  uint8_t buffer[4096];
  size_t n = 0;
  while ((n = fread(buffer, 1, sizeof buffer, stdin)) > 0) {
    ms_strbuild_append(&all, ms_span_of(buffer, n));
  }
  *out = ms_arena_copy(arena, ms_strbuild_span(&all));
  ms_strbuild_free(&all);
  return true;
}

/* Maps the diff onto the project and rebuilds each changed `.ms` file's base text. False leaves the reason. */
static bool review_input(MsArena *arena, const MsDiffFiles *files, MsSpan root, MsDiffInput *input, OverlayList *overlay,
                         MsSpan *error) {
  input->files = files->len;
  for (size_t f = 0; f < files->len; f++) {
    const MsDiffFile *file = &files->ptr[f];
    const MsSpan name = ms_diff_path(file);
    for (size_t h = 0; h < file->hunks.len; h++) {
      for (size_t l = 0; l < file->hunks.ptr[h].lines.len; l++) {
        const MsSpan line = file->hunks.ptr[h].lines.ptr[l];
        input->insertions += line.len > 0 && line.ptr[0] == '+' ? 1 : 0;
        input->deletions += line.len > 0 && line.ptr[0] == '-' ? 1 : 0;
      }
    }
    if (!ms_span_equal(ms_path_ext(name), ms_span_of_text(".ms"))) {
      continue;
    }
    const bool deleted = file->new.len == 0;
    const MsSpan absolute = locate_diff_path(arena, root, name, deleted);
    MsStrBuild rel = ms_strbuild_new();
    const bool related = ms_path_relative(&rel, root, absolute);
    const MsSpan relative = ms_message_take_builder(arena, &rel);
    if (!related || ms_path_escapes(relative)) {
      continue;
    }
    input->sources++;
    MsSpan head = {0};
    if (deleted) {
      if (path_exists(absolute)) {
        *error = ms_message_format(arena, "%S: deleted source still exists in the working tree", name, (MsSpan){0});
        return false;
      }
    } else if (!read_text(arena, absolute, &head)) {
      *error = ms_message_format(arena, "%S: cannot open %S", name, absolute);
      return false;
    }
    MsSpan base = {0};
    MsSpan reason = {0};
    if (!ms_diff_reverse_apply(arena, head, &file->hunks, &base, &reason)) {
      *error = ms_message_format(arena, "%S: %S", name, reason);
      return false;
    }
    if (!deleted && file->old.len == 0) {
      if (base.len > 0) {
        *error = ms_message_format(arena, "%S: added source diff does not cover the whole file", name, (MsSpan){0});
        return false;
      }
      ms_spans_push(arena, &input->added, relative);
    } else {
      overlay_push(arena, overlay, (MsOverlayFile){.path = absolute, .text = base});
    }
    if (!deleted) {
      int64_t *lines = NULL;
      size_t count = 0;
      ms_diff_touched(arena, file, &lines, &count);
      ms_touched_list_push(arena, &input->touched, (MsTouched){.file = relative, .lines = lines, .count = count});
    }
  }
  return true;
}

/* Reads the diff and rebuilds the base program from it. Returns 0, or the status of a problem already reported. */
int ms_review_diff_inputs(MsArena *arena, const MsCheckedInput *head, const MsInvocation *invocation, MsDiffInput *input,
                       MsFactModel *base_facts, MsCheckedInput *base) {
  MsSpan text = {0};
  if (ms_span_equal(invocation->diff, ms_span_of_text("-"))) {
    (void)read_stdin(arena, &text);
  } else if (!read_text(arena, invocation->diff, &text)) {
    (void)fprintf(stderr, "ms map --view review: cannot read the diff: cannot open %.*s\n", (int)invocation->diff.len,
                  (const char *)invocation->diff.ptr);
    return 2;
  }
  MsDiffFiles files = {0};
  MsSpan error = {0};
  if (!ms_diff_parse(arena, text, &files, &error)) {
    (void)fprintf(stderr, "ms map --view review: %.*s; pass a unified diff such as git diff --no-renames main...\n", (int)error.len,
                  (const char *)error.ptr);
    return 2;
  }
  MsSpan root = head->graph.project_root;
  if (root.len == 0) {
    MsString real = {0};
    if (!ms_file_real_path(invocation->filename, &real)) {
      (void)fprintf(stderr, "cannot open %.*s\n", (int)invocation->filename.len, (const char *)invocation->filename.ptr);
      return 2;
    }
    root = path_dir(arena, ms_string_span(&real));
    ms_string_release(&real);
  }
  OverlayList overlay = {0};
  if (!review_input(arena, &files, root, input, &overlay, &error)) {
    (void)fprintf(stderr, "ms map --view review: diff does not match the tree: %.*s; run it from the checkout the diff was made against\n",
                  (int)error.len, (const char *)error.ptr);
    return 2;
  }
  const MsOverlay view = {.files = overlay.ptr, .count = overlay.len};
  const MsLoadOptions options = {.project_sources = true, .overlay = &view};
  if (ms_checked_input_load_with(arena, base, invocation->filename, MS_INPUT_ANALYSIS, &options)) {
    input->base_checked = true;
    *base_facts = ms_facts_collect(arena, &base->program);
  }
  return 0;
}

static int review(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation) {
  const MsSpan format = invocation->json ? ms_span_of_text("json") : invocation->format.len > 0 ? invocation->format : ms_span_of_text("ascii");
  const MsFactModel head = ms_facts_collect(arena, &checked->program);
  const MsReviewOptions options = {.all = invocation->all || invocation->json, .effect = invocation->effect};
  MsStrBuild text = ms_strbuild_new();
  int status = 0;
  if (invocation->diff.len == 0) {
    const MsReport report = ms_project_report(arena, &head, options);
    ms_report_render(arena, &report, format, &text);
    status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
    return status;
  }
  MsDiffInput input = {0};
  MsFactModel base_facts = {0};
  MsCheckedInput base = {0};
  status = ms_review_diff_inputs(arena, checked, invocation, &input, &base_facts, &base);
  if (status == 0 && invocation->explain.len > 0) {
    const MsFindings findings = ms_compare_facts(arena, &base_facts, &head, &input);
    MsSpan error = {0};
    const bool json = ms_span_equal(format, ms_span_of_text("json"));
    const bool ok = json ? ms_review_explain_json(arena, &findings, &head, invocation->explain, &text, &error)
                         : ms_review_explain(arena, &findings, &head, invocation->explain, &text, &error);
    if (ok) {
      status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
    } else {
      (void)fprintf(stderr, "ms map --view review: %.*s\n", (int)error.len, (const char *)error.ptr);
      status = 2;
    }
  } else if (status == 0) {
    const MsReport report = ms_diff_report(arena, &base_facts, &head, &input, options);
    ms_report_render(arena, &report, format, &text);
    status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
  }
  ms_strbuild_free(&text);
  ms_checked_input_free(&base);
  return status;
}

int ms_review_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "review", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load_with(&arena, &checked, invocation.filename, MS_INPUT_ANALYSIS, &(const MsLoadOptions){.project_sources = true})) {
      status = review(&arena, &checked, &invocation);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
