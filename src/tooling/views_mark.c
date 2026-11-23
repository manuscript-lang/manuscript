/* Owns the marking of a view tree by a diff: `--diff` of `ms diagram`. */
#include "tooling/views.h"

static bool touched_line(const MsTouchedList *touched, MsSpan file, size_t line) {
  for (size_t i = 0; i < touched->len; i++) {
    if (!ms_span_equal(touched->ptr[i].file, file)) {
      continue;
    }
    for (size_t k = 0; k < touched->ptr[i].count; k++) {
      if (touched->ptr[i].lines[k] == (int64_t)line) {
        return true;
      }
    }
  }
  return false;
}

/* The mark of the finding with `id`, or an empty span. The rank counts the findings that are not internal. */
static MsSpan finding_mark(MsArena *arena, const MsFindings *findings, MsSpan id) {
  size_t rank = 0;
  for (size_t i = 0; i < findings->len; i++) {
    const MsFinding *finding = &findings->ptr[i];
    const bool internal = ms_span_is_text(finding->tier, MS_TIER_INTERNAL);
    rank += internal ? 0 : 1;
    if (!ms_span_equal(finding->id, id)) {
      continue;
    }
    return internal ? ms_span_of_text("  <- INTERNAL") : ms_message_format(arena, "  <- %S #%z", finding->tier, rank);
  }
  return (MsSpan){0};
}

static void mark_node(MsArena *arena, MsViewNode *node, const MsFindings *findings, const MsTouchedList *touched) {
  const MsSpan mark = node->reference.len > 0 ? finding_mark(arena, findings, node->reference) : (MsSpan){0};
  if (mark.len > 0) {
    node->label = ms_message_format(arena, "%S%S", node->label, mark);
  } else if (node->line > 0 && touched_line(touched, node->file, node->line)) {
    node->label = ms_message_format(arena, "%S  <- changed", node->label, (MsSpan){0});
  }
  for (size_t i = 0; i < node->kids.len; i++) {
    mark_node(arena, node->kids.ptr[i], findings, touched);
  }
}

void ms_view_mark_changes(MsArena *arena, MsViewNode *root, const MsFindings *findings, const MsTouchedList *touched) {
  mark_node(arena, root, findings, touched);
}
