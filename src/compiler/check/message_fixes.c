/* compiler/check/message_fixes.c: the edit a `; did you mean 'x'?` hint names (see message_fixes.h). */
#include "compiler/check/message_fixes.h"

static bool is_word_byte(uint8_t byte) {
  return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') || byte == '_';
}

/* The one name a trailing `; did you mean 'name'?` suggests; empty when there is none or several. */
static MsSpan single_suggestion(MsSpan message) {
  static const char MARK[] = "; did you mean '";
  const size_t mark = sizeof(MARK) - 1;
  for (size_t at = 0; at + mark < message.len; at++) {
    if (__builtin_memcmp(message.ptr + at, MARK, mark) != 0) {
      continue;
    }
    const uint8_t *name = message.ptr + at + mark;
    const size_t room = message.len - at - mark;
    size_t length = 0;
    while (length < room && name[length] != '\'') {
      length++;
    }
    const bool last = length > 0 && length + 2 == room && name[length + 1] == '?';
    return last ? ms_span_of(name, length) : (MsSpan){0};
  }
  return (MsSpan){0};
}

void ms_check_attach_message_fixes(MsCheckProgram *program) {
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    MsCheckDiag *diag = &program->diagnostics.ptr[index];
    const MsSpan source = program->modules.ptr[diag->module].source;
    const MsSpan name = single_suggestion(ms_string_span(&diag->message));
    /* an arm naming no case of the enum is reported without an edit */
    if (diag->has_fix || diag->stage == MS_STAGE_IMPORTS || ms_span_starts_with_text(ms_string_span(&diag->message), "unknown case ") || name.len == 0 || diag->pos.offset >= source.len) {
      continue;
    }
    size_t length = 0;
    while (diag->pos.offset + length < source.len && is_word_byte(source.ptr[diag->pos.offset + length])) {
      length++;
    }
    if (length == 0) {
      continue;
    }
    diag->has_fix = true;
    diag->fix_pos = diag->pos;
    diag->fix_end = (MsPos){.line = diag->pos.line, .column = diag->pos.column + (uint32_t)length,
                            .offset = diag->pos.offset + (uint32_t)length};
    diag->fix_text = ms_string_from_span(name);
  }
}
