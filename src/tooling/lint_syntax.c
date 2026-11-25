/* Owns the syntax-only lint of lint.h: the rules that need a parse and no type checking, over a source file or the
 * code fences of a Markdown file. */
#include "base/strbuild.h"
#include "base/message.h"
#include "compiler/syntax/parse.h"
#include "tooling/lint.h"

static const char ALLOWANCE[] = "// manuscript:allow-nested-match ";

/* One line of `text` (without its newline), 1-based; empty past the end. */
static MsSpan line_of(MsSpan text, size_t number) {
  size_t line = 1;
  size_t start = 0;
  for (size_t i = 0; i < text.len && line < number; i++) {
    if (text.ptr[i] == '\n') {
      line++;
      start = i + 1;
    }
  }
  if (line != number) {
    return (MsSpan){0};
  }
  size_t end = start;
  while (end < text.len && text.ptr[end] != '\n') {
    end++;
  }
  return (MsSpan){.ptr = text.ptr + start, .len = end - start};
}

static MsSpan trimmed(MsSpan text) {
  while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t')) {
    text.ptr++;
    text.len--;
  }
  while (text.len > 0 && (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\t' || text.ptr[text.len - 1] == '\r')) {
    text.len--;
  }
  return text;
}

static size_t indent_of(MsSpan line) {
  size_t n = 0;
  while (n < line.len && (line.ptr[n] == ' ' || line.ptr[n] == '\t')) {
    n++;
  }
  return n;
}

/* Whether the line before `line` of `code` carries the allowance with a reason. */
static bool allowed(MsSpan code, size_t line) {
  if (line < 2) {
    return false;
  }
  const MsSpan before = trimmed(line_of(code, line - 1));
  const MsSpan prefix = ms_span_of_text(ALLOWANCE);
  return ms_span_starts_with_text(before, "// manuscript:allow-nested-match") && before.len > prefix.len &&
         trimmed((MsSpan){.ptr = before.ptr + prefix.len, .len = before.len - prefix.len}).len > 0;
}

/* `code` as the body of a function, every line indented once, so statements parse. */
static MsSpan wrapped(MsArena *arena, MsSpan code, size_t *removed_indent) {
  size_t common = SIZE_MAX;
  for (size_t line = 1;; line++) {
    const MsSpan text = line_of(code, line);
    if (text.ptr == NULL) {
      break;
    }
    if (trimmed(text).len != 0 && indent_of(text) < common) {
      common = indent_of(text);
    }
  }
  *removed_indent = common == SIZE_MAX ? 0 : common;
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "fn fragment() Void {\n");
  for (size_t line = 1;; line++) {
    const MsSpan text = line_of(code, line);
    if (text.ptr == NULL) {
      break;
    }
    ms_strbuild_append_text(&out, "    ");
    ms_strbuild_append(&out, (MsSpan){.ptr = text.ptr + (text.len >= common ? common : 0),
                                      .len = text.len - (text.len >= common ? common : 0)});
    ms_strbuild_append_byte(&out, '\n');
  }
  ms_strbuild_append_text(&out, "}\n");
  const MsSpan result = ms_message_take_builder(arena, &out);
  return result;
}

/* Lints one unit of code whose first line is line `first_line` of its file. */
static void lint_unit(MsArena *arena, MsSpan file, MsSpan code, size_t first_line, MsLintFindingList *findings) {
  MsNames names;
  ms_names_init(&names);
  MsModule module = {0};
  MsDiag diag = {0};
  size_t shift = 0;
  size_t removed = 0;
  bool parsed = ms_parse(arena, &names, code, &module, &diag);
  if (!parsed || module.ndecls == 0) {
    module = (MsModule){0};
    diag = (MsDiag){0};
    parsed = ms_parse(arena, &names, wrapped(arena, code, &removed), &module, &diag);
    shift = 1;
  }
  if (parsed) {
    const size_t start = findings->len;
    ms_lint_nested_matches(&module, file, findings);
    size_t kept = start;
    for (size_t i = start; i < findings->len; i++) {
      MsLintFinding *finding = &findings->ptr[i];
      const size_t within = finding->pos.line - shift;
      if (allowed(code, within)) {
        continue;
      }
      finding->pos.line = (uint32_t)(first_line + within - 1);
      if (shift != 0 && finding->pos.column > 4) {
        finding->pos.column = (uint32_t)(finding->pos.column - 4 + removed);
      }
      findings->ptr[kept++] = *finding;
    }
    findings->len = kept;
  }
  ms_names_free(&names);
}

/* The info string of a fence that holds Manuscript, or empty. */
static bool is_code_fence(MsSpan line) {
  return ms_span_is_text(line, "```manuscript") || ms_span_is_text(line, "```ms") || ms_span_is_text(line, "```text");
}

static void lint_fences(MsArena *arena, MsSpan file, MsSpan source, MsLintFindingList *findings) {
  size_t body_start = 0;
  size_t body_line = 0;
  bool open = false;
  size_t offset = 0;
  for (size_t line = 1; offset <= source.len; line++) {
    size_t end = offset;
    while (end < source.len && source.ptr[end] != '\n') {
      end++;
    }
    MsSpan text = {.ptr = source.ptr + offset, .len = end - offset};
    if (text.len > 0 && text.ptr[text.len - 1] == '\r') {
      text.len--;
    }
    if (!open && is_code_fence(text)) {
      open = true;
      body_start = end < source.len ? end + 1 : end;
      body_line = line + 1;
    } else if (open && ms_span_is_text(text, "```")) {
      open = false;
      const MsSpan code = {.ptr = source.ptr + body_start, .len = offset >= body_start ? offset - body_start : 0};
      lint_unit(arena, file, code, body_line, findings);
    }
    if (end >= source.len) {
      break;
    }
    offset = end + 1;
  }
}

void ms_lint_syntax(MsArena *arena, MsSpan file, MsSpan source, MsLintFindingList *findings) {
  if (ms_span_ends_with_text(file, ".md")) {
    lint_fences(arena, file, source, findings);
  } else {
    lint_unit(arena, file, source, 1, findings);
  }
}
