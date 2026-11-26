/* cli/diagram_command.c: `ms map`. */
#include "cli/files.h"
#include "cli/diagram_command.h"

#include <stdio.h>

#include "base/file.h"
#include "tooling/checked_input.h"
#include "compiler/syntax/diag_json.h"
#include "cli/invocation.h"
#include "cli/review_command.h"
#include "tooling/html.h"
#include "tooling/inspect.h"
#include "tooling/views.h"

enum { STATUS_FAILED = 1, EXIT_USAGE = 2 };

static int call_graph(MsArena *arena, const MsCheckedInput *checked, const MsInvocation *invocation) {
  MsInspection inspection = {0};
  ms_inspect_collect(arena, &checked->program, false, &inspection);
  MsStrBuild text = ms_strbuild_new();
  if (ms_span_is_text(invocation->format, "mermaid")) {
    ms_diagram_mermaid(&inspection, arena, &text);
  } else {
    ms_diagram_ascii(&inspection, arena, &text);
  }
  const int status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  ms_inspection_free(&inspection);
  return status;
}

/* The text of a view: the `--json` document, Mermaid, or the view's own or the generic outline. */
static void render_view(MsArena *arena, const MsFactModel *model, const MsInvocation *invocation, MsSpan view,
                        const MsViewNode *tree, MsStrBuild *text) {
  /* A diff marks the generic tree, so it keeps the generic rendering. */
  const bool generic = invocation->diff.len > 0;
  const int64_t depth = (int64_t)invocation->depth;
  if (invocation->json) {
    ms_strbuild_append_text(text, "{\n  \"format\": 1,\n  \"view\": ");
    ms_json_string(text, view);
    ms_strbuild_append_text(text, ",\n  \"entity\": ");
    ms_json_string(text, invocation->entity);
    ms_strbuild_append_text(text, ",\n  \"tree\": ");
    ms_view_json(tree, 1, text);
    ms_strbuild_append_text(text, "\n}\n\n"); /* the Rust CLI adds a newline to a line that already has one */
  } else if (ms_span_is_text(invocation->format, "mermaid")) {
    if (generic || !ms_view_mermaid_custom(arena, model, view, invocation->entity, depth, text)) {
      ms_view_mermaid(tree, text);
    }
  } else if (generic || !ms_view_ascii_custom(arena, model, view, invocation->entity, depth, text)) {
    ms_view_ascii(tree, text);
  }
}

/* The whole program as one page; with `--diff`, the entities and findings the diff changed. */
static int html_command(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation, const MsFactModel *model) {
  MsFindings findings = {0};
  bool has_changes = false;
  MsCheckedInput base = {0};
  if (invocation->diff.len > 0) {
    MsDiffInput input = {0};
    MsFactModel base_facts = {0};
    const int status = ms_review_diff_inputs(arena, checked, invocation, &input, &base_facts, &base);
    if (status != 0) {
      ms_checked_input_free(&base);
      return status;
    }
    findings = ms_compare_facts(arena, &base_facts, model, &input);
    has_changes = true;
  }
  MsStrBuild text = ms_strbuild_new();
  const MsOccurrences index = ms_occurrence_index(arena, &checked->program);
  const MsTypeHints hints = ms_occurrence_type_hints(arena, &checked->program, &index);
  ms_html_page(arena, model, has_changes ? &findings : NULL, &hints, &text);
  const int status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  ms_checked_input_free(&base);
  return status;
}

static int view_command(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation) {
  const MsSpan view = invocation->view.len == 0 ? ms_span_of_text("calls") : invocation->view;
  const MsFactModel model = ms_facts_collect(arena, &checked->program);
  if (ms_span_is_text(invocation->format, "html")) {
    return html_command(arena, checked, invocation, &model);
  }
  MsViewNode *tree = NULL;
  MsSpan error = {0};
  if (!ms_build_view(arena, &model, view, invocation->entity, (int64_t)invocation->depth, &tree, &error)) {
    (void)fprintf(stderr, "ms map: %.*s\n", (int)error.len, (const char *)error.ptr);
    return EXIT_USAGE;
  }
  MsCheckedInput base = {0};
  if (invocation->diff.len > 0) {
    MsDiffInput input = {0};
    MsFactModel base_facts = {0};
    const int status = ms_review_diff_inputs(arena, checked, invocation, &input, &base_facts, &base);
    if (status != 0) {
      ms_checked_input_free(&base);
      return status;
    }
    const MsFindings findings = ms_compare_facts(arena, &base_facts, &model, &input);
    ms_view_mark_changes(arena, tree, &findings, &input.touched);
  }
  MsStrBuild text = ms_strbuild_new();
  render_view(arena, &model, invocation, view, tree, &text);
  const int status = ms_cli_write_output(invocation->output, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  ms_checked_input_free(&base);
  return status;
}

static int diagram(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation) {
  if (invocation->json || invocation->view.len > 0 || invocation->entity.len > 0 ||
      ms_span_is_text(invocation->format, "html")) {
    return view_command(arena, checked, invocation);
  }
  return call_graph(arena, checked, invocation);
}

int ms_diagram_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "diagram", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_ANALYSIS)) {
      status = diagram(&arena, &checked, &invocation);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
