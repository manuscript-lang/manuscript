/* Owns text building (see strbuild.h). */
#include "base/strbuild.h"

#include "base/fatal.h"

void ms_strbuild_append(MsStrBuild *builder, MsSpan text) {
  if (text.len == 0) {
    return;
  }
  uint8_t *destination = ms_list_extend(&builder->bytes, 1, text.len);
  __builtin_memcpy(destination, text.ptr, text.len);
}

void ms_strbuild_append_text(MsStrBuild *builder, const char *text) {
  ms_strbuild_append(builder, ms_span_of_text(text));
}

void ms_strbuild_append_byte(MsStrBuild *builder, uint8_t byte) {
  ms_list_push(&builder->bytes, 1, &byte);
}

void ms_strbuild_append_string(MsStrBuild *builder, const MsString *string) {
  ms_strbuild_append(builder, ms_string_span(string));
}

void ms_strbuild_append_u64_radix(MsStrBuild *builder, uint64_t value, unsigned radix) {
  if (radix < 2 || radix > 16) {
    ms_fatal(MS_FATAL_INVARIANT, "radix out of range");
  }
  uint8_t digits[64];
  size_t count = 0;
  do {
    digits[count++] = (uint8_t) "0123456789abcdef"[value % radix];
    value /= radix;
  } while (value != 0);
  uint8_t *destination = ms_list_extend(&builder->bytes, 1, count);
  for (size_t i = 0; i < count; i++) {
    destination[i] = digits[count - 1 - i];
  }
}

void ms_strbuild_append_indent(MsStrBuild *builder, size_t depth) {
  for (size_t i = 0; i < depth; i++) {
    ms_strbuild_append_text(builder, "  ");
  }
}

void ms_strbuild_append_u64(MsStrBuild *builder, uint64_t value) {
  ms_strbuild_append_u64_radix(builder, value, 10);
}

void ms_strbuild_append_i64(MsStrBuild *builder, int64_t value) {
  if (value < 0) {
    ms_strbuild_append_byte(builder, '-');
    ms_strbuild_append_u64(builder, 0 - (uint64_t)value);
    return;
  }
  ms_strbuild_append_u64(builder, (uint64_t)value);
}

void ms_strbuild_append_utf8(MsStrBuild *builder, uint32_t scalar) {
  if (scalar < 0x80) {
    ms_strbuild_append_byte(builder, (uint8_t)scalar);
  } else if (scalar < 0x800) {
    ms_strbuild_append_byte(builder, (uint8_t)(0xC0 | (scalar >> 6)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | (scalar & 0x3F)));
  } else if (scalar < 0x10000) {
    ms_strbuild_append_byte(builder, (uint8_t)(0xE0 | (scalar >> 12)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | ((scalar >> 6) & 0x3F)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | (scalar & 0x3F)));
  } else {
    ms_strbuild_append_byte(builder, (uint8_t)(0xF0 | (scalar >> 18)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | ((scalar >> 12) & 0x3F)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | ((scalar >> 6) & 0x3F)));
    ms_strbuild_append_byte(builder, (uint8_t)(0x80 | (scalar & 0x3F)));
  }
}

MsString ms_strbuild_finish(MsStrBuild *builder) {
  const MsString text = ms_string_from_span(ms_strbuild_span(builder));
  ms_strbuild_free(builder);
  return text;
}

void ms_strbuild_free(MsStrBuild *builder) {
  ms_list_free(&builder->bytes);
}
