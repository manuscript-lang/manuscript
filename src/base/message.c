/* Owns message construction: joins parts and numbers into arena text. */
#include "base/message.h"

#include "base/chars.h"

MsSpan ms_message_from_builder(MsArena *arena, const MsStrBuild *builder) {
  return ms_arena_copy(arena, ms_strbuild_span(builder));
}

MsSpan ms_message_take_builder(MsArena *arena, MsStrBuild *builder) {
  const MsSpan text = ms_message_from_builder(arena, builder);
  ms_strbuild_free(builder);
  return text;
}

MsSpan ms_message_join(MsArena *arena, const MsSpan *parts, size_t count) {
  MsStrBuild builder = ms_strbuild_new();
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_append(&builder, parts[index]);
  }
  MsSpan joined = ms_message_from_builder(arena, &builder);
  ms_strbuild_free(&builder);
  return joined;
}

MsSpan ms_message_lowered(MsArena *arena, MsSpan text) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < text.len; i++) {
    ms_strbuild_append_byte(&out, ms_ascii_to_lower(text.ptr[i]));
  }
  MsSpan copy = ms_message_from_builder(arena, &out);
  ms_strbuild_free(&out);
  return copy;
}

static void append_conversion(MsStrBuild *builder, char conversion, va_list *arguments) {
  switch (conversion) {
  case 's':
    ms_strbuild_append_text(builder, va_arg(*arguments, const char *));
    return;
  case 'S':
    ms_strbuild_append(builder, *va_arg(*arguments, const MsSpan *));
    return;
  case 'z':
    ms_strbuild_append_u64(builder, va_arg(*arguments, size_t));
    return;
  case 'u':
    ms_strbuild_append_u64(builder, va_arg(*arguments, unsigned));
    return;
  case 'c':
    ms_strbuild_append_byte(builder, (uint8_t)va_arg(*arguments, int));
    return;
  default:
    ms_strbuild_append_byte(builder, (uint8_t)conversion);
    return;
  }
}

MsSpan ms_message_vformat(MsArena *arena, const char *format, va_list arguments) {
  MsStrBuild builder = ms_strbuild_new();
  va_list cursor;
  va_copy(cursor, arguments);
  MsSpan text = ms_span_of_text(format);
  for (size_t index = 0; index < text.len; index++) {
    if (text.ptr[index] != '%' || index + 1 == text.len) {
      ms_strbuild_append_byte(&builder, text.ptr[index]);
      continue;
    }
    index++;
    append_conversion(&builder, (char)text.ptr[index], &cursor);
  }
  va_end(cursor);
  MsSpan message = ms_message_from_builder(arena, &builder);
  ms_strbuild_free(&builder);
  return message;
}

MsSpan ms_message_format_(MsArena *arena, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  MsSpan message = ms_message_vformat(arena, format, arguments);
  va_end(arguments);
  return message;
}
