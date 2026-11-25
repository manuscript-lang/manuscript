/* Owns fmt_labels.h: `analysis` of one file. */
#include "cli/fmt_labels.h"

#include "base/message.h"
#include "compiler/check/drop_labels.h"
#include "compiler/own/own.h"
#include "compiler/project/project.h"

/* The message for source that does not check: its first problem and how many there are. */
static MsSpan unchecked(MsArena *arena, MsSpan display, const MsGraph *graph, const MsCheckProgram *program,
                        const MsNames *names) {
  size_t count = graph->diagnostic_count + (program->names == NULL ? 0 : program->diagnostics.len);
  MsPos pos = {0};
  const char *phase = "resolution";
  MsSpan message = {0};
  if (graph->diagnostic_count > 0) {
    pos = graph->diagnostics[0].diag.pos;
    phase = graph->diagnostics[0].phase == MS_GRAPH_PARSE ? "parse" : "resolution";
    message = graph->diagnostics[0].diag.message;
  } else if (count > 0) {
    const MsCheckDiag *first = &program->diagnostics.ptr[0];
    pos = first->pos;
    phase = first->phase == MS_CHECK_RESOLUTION ? "resolution" : "type";
    message = ms_string_span(&first->message);
  } else {
    return ms_message_format(arena, "%S: --drop-labels needs source that checks", display);
  }
  (void)names;
  return ms_message_format(arena,
                           "%S:%u:%u: %s: %S\n--drop-labels needs source that checks (%z error(s)); fix them, then "
                           "re-run ms fmt --drop-labels %S",
                           display, pos.line, pos.column, phase, message, count, display);
}

bool fmt_drop_labels(MsArena *arena, MsSpan path, MsSpan display, MsSpan source, MsSpan *edited, MsSpan *error) {
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  const MsLoadOptions load = {0};
  ms_project_load(arena, &names, path, &load, &graph);
  MsCheckProgram program = {0};
  if (graph.diagnostic_count == 0) {
    ms_check_graph(&program, &names, &graph);
    ms_own_check(&program);
  }
  const bool clean = graph.diagnostic_count == 0 && program.diagnostics.len == 0;
  *edited = source;
  if (!clean) {
    *error = unchecked(arena, display, &graph, &program, &names);
  } else {
    for (uint32_t i = 0; i < graph.count; i++) {
      if (ms_span_equal(graph.modules[i].source, source)) {
        *edited = ms_drop_redundant_labels(arena, &program, i, source);
        break;
      }
    }
  }
  if (program.names != NULL) {
    ms_check_program_free(&program);
  }
  ms_names_free(&names);
  return clean;
}
