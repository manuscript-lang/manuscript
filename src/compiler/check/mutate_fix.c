/* compiler/check/mutate_fix.c: reading a binding's declaration to build the `var` rewrite. */
#include "compiler/check/mutate_fix.h"
#include "base/chars.h"

static bool is_word_byte(uint8_t byte) {
  return ms_ascii_is_alnum(byte) || byte == '_';
}

/* The offset of the first `:=` in `line`, or SIZE_MAX. */
static size_t find_walrus(MsSpan line) {
  for (size_t index = 0; index + 1 < line.len; index++) {
    if (line.ptr[index] == ':' && line.ptr[index + 1] == '=') {
      return index;
    }
  }
  return SIZE_MAX;
}

static bool has_stop(MsSpan text) {
  for (size_t index = 0; index < text.len; index++) {
    if (text.ptr[index] == ',' || text.ptr[index] == ')') {
      return true;
    }
  }
  return false;
}

static MsSpan trim_end_spaces(MsSpan text) {
  size_t end = text.len;
  while (end > 0 && ms_ascii_is_space(text.ptr[end - 1])) {
    end--;
  }
  return ms_span_of(text.ptr, end);
}

/* After `name`: how many bytes the edit covers and the text after `var name`. */
static bool rewrite(MsSpan name, MsSpan after, size_t *length, MsStrBuild *text) {
  size_t spaces = 0;
  while (spaces < after.len && after.ptr[spaces] == ' ') {
    spaces++;
  }
  const MsSpan rest = ms_span_of(after.ptr + spaces, after.len - spaces);
  if (ms_span_starts_with(rest, ms_span_of_text(":="))) {
    *length = name.len + spaces + 2;
    ms_strbuild_append_text(text, "var ");
    ms_strbuild_append(text, name);
    ms_strbuild_append_text(text, " =");
    return true;
  }
  if (rest.len == 0 || rest.ptr[0] != ':') {
    return false;
  }
  size_t line_length = 0;
  while (line_length < after.len && after.ptr[line_length] != '\n') {
    line_length++;
  }
  const MsSpan line = ms_span_of(after.ptr, line_length);
  const size_t walrus = find_walrus(line);
  ms_strbuild_append_text(text, "var ");
  ms_strbuild_append(text, name);
  if (walrus == SIZE_MAX || has_stop(ms_span_of(line.ptr, walrus))) {
    *length = name.len;
    return true;
  }
  ms_strbuild_append(text, trim_end_spaces(ms_span_of(after.ptr, walrus)));
  ms_strbuild_append_text(text, " =");
  *length = name.len + walrus + 2;
  return true;
}

bool ms_var_fix(MsSpan source, MsPos decl, MsVarFix *fix) {
  if (decl.offset >= source.len) {
    return false;
  }
  const MsSpan from = ms_span_of(source.ptr + decl.offset, source.len - decl.offset);
  size_t name_length = 0;
  while (name_length < from.len && is_word_byte(from.ptr[name_length])) {
    name_length++;
  }
  if (name_length == 0) {
    return false;
  }
  MsStrBuild text = ms_strbuild_new();
  size_t length = 0;
  const MsSpan name = ms_span_of(from.ptr, name_length);
  if (!rewrite(name, ms_span_of(from.ptr + name_length, from.len - name_length), &length, &text)) {
    ms_strbuild_free(&text);
    return false;
  }
  fix->pos = decl;
  fix->end = (MsPos){.offset = decl.offset + (uint32_t)length, .line = decl.line,
                     .column = decl.column + (uint32_t)length};
  fix->replacement = ms_strbuild_finish(&text);
  return true;
}
