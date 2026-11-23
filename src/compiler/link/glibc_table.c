/* Owns reading the table of glibc exports (see glibc_table.h). */
#include "compiler/link/glibc_table.h"

#include "base/chars.h"

enum { FIELD_COUNT = 6, FIELD_WITH_SIZE = 4, FIELD_ALIAS = 5 };

/* Splits `line` into blank-separated fields; returns how many (at most FIELD_COUNT). */
static size_t split_fields(MsSpan line, MsSpan fields[FIELD_COUNT]) {
  size_t count = 0;
  size_t index = 0;
  while (index < line.len && count < FIELD_COUNT) {
    while (index < line.len && (line.ptr[index] == ' ' || line.ptr[index] == '\t')) {
      index++;
    }
    size_t start = index;
    while (index < line.len && line.ptr[index] != ' ' && line.ptr[index] != '\t') {
      index++;
    }
    if (index > start) {
      fields[count++] = ms_span_of(line.ptr + start, index - start);
    }
  }
  return count;
}

/* The value of hex digits, with an optional `0x` prefix; reading stops at the first other byte. */
static uint64_t parse_hex(MsSpan digits) {
  bool prefixed = digits.len > 2 && digits.ptr[0] == '0' && digits.ptr[1] == 'x';
  uint64_t value = 0;
  uint32_t digit = 0;
  for (size_t index = prefixed ? 2 : 0; index < digits.len && ms_hex_digit_value(digits.ptr[index], &digit); index++) {
    value = value * 16 + digit;
  }
  return value;
}

static void parse_line(MsSpan line, GlibcExportList *out) {
  MsSpan fields[FIELD_COUNT];
  size_t count = split_fields(line, fields);
  if (count < FIELD_WITH_SIZE || fields[0].ptr[0] == '#') {
    return;
  }
  GlibcExport entry = {.soname = fields[0], .version = fields[1], .name = fields[2], .data = fields[3].ptr[0] == 'D'};
  if (entry.data && count > FIELD_WITH_SIZE) {
    entry.size = parse_hex(fields[FIELD_WITH_SIZE]);
  }
  if (entry.data && count > FIELD_ALIAS) {
    entry.alias_of = fields[FIELD_ALIAS];
  }
  glibc_export_list_push(out, entry);
}

void glibc_table_parse(MsSpan text, GlibcExportList *out) {
  size_t at = 0;
  while (at < text.len) {
    size_t end = at;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    parse_line(ms_span_of(text.ptr + at, end - at), out);
    at = end + 1;
  }
}
