/* compiler/project/project.c: error text and the bundled standard-library table. */
#include "compiler/project/project_internal.h"

#include "base/ostext.h"

MsSpan ms_project_text(MsArena *arena, MsStrBuild *builder) {
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(builder));
  ms_strbuild_free(builder);
  return text;
}

void ms_project_error_message(MsProjectError *error, MsSpan message) {
  *error = (MsProjectError){.kind = MS_PERR_MESSAGE, .message = message};
}

void ms_project_error_path(MsProjectError *error, const char *op, MsSpan path, int os_error) {
  *error = (MsProjectError){
      .kind = MS_PERR_PATH, .op = ms_span_of_text(op), .path = path, .os_error = os_error};
}

/* Go spells an error number in lower case with no trailing detail. */
static void append_errno_text(MsStrBuild *out, int os_error) {
  const size_t start = ms_strbuild_length(out);
  ms_os_error_text(os_error, out);
  if (ms_strbuild_length(out) > start && out->bytes.ptr[start] >= 'A' && out->bytes.ptr[start] <= 'Z') {
    out->bytes.ptr[start] = (uint8_t)(out->bytes.ptr[start] + ('a' - 'A'));
  }
}

MsSpan ms_project_error_text(MsArena *arena, const MsProjectError *error) {
  MsStrBuild text = ms_strbuild_new();
  switch (error->kind) {
  case MS_PERR_NONE:
    break;
  case MS_PERR_PATH:
    ms_strbuild_append(&text, error->op);
    ms_strbuild_append_byte(&text, ' ');
    ms_strbuild_append(&text, error->path);
    ms_strbuild_append_text(&text, ": ");
    append_errno_text(&text, error->os_error);
    break;
  case MS_PERR_MESSAGE:
    ms_strbuild_append(&text, error->message);
    break;
  case MS_PERR_MANIFEST:
    ms_strbuild_append(&text, error->file);
    ms_strbuild_printf(&text, ":%u:%u: ", error->position.line, error->position.column);
    ms_strbuild_append(&text, error->message);
    break;
  }
  return ms_project_text(arena, &text);
}

bool ms_std_source_find(MsSpan name, MsStdSource *out) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  for (size_t i = 0; i < count; i++) {
    if (ms_span_equal(sources[i].name, name)) {
      *out = sources[i];
      return true;
    }
  }
  return false;
}
