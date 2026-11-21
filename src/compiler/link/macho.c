/* Owns reading symbol tables out of Mach-O objects and archives (see macho.h). */
#include "compiler/link/macho.h"

#include "base/chars.h"

#define MACHO_MAGIC_64 0xfeedfacfu

enum {
  LC_SEGMENT_64 = 0x19,
  LC_SYMTAB = 0x2,
  N_EXT = 0x01,
  N_PEXT = 0x10,
  N_STAB = 0xe0,
  N_TYPE = 0x0e,
  HEADER_SIZE = 32,
  SEGMENT_SIZE = 72,
  SECTION_SIZE = 80,
  NLIST_SIZE = 16,
  ARCHIVE_HEADER_SIZE = 60,
  ARCHIVE_SIZE_OFFSET = 48,
  ARCHIVE_SIZE_DIGITS = 10
};

/* Whether `[at, at + size)` lies inside `length` bytes. */
static bool within(size_t length, uint64_t at, uint64_t size) {
  return at <= length && size <= length - at;
}

static uint32_t word32(MsSpan data, size_t at) {
  return ms_load32(data.ptr + at); /* the hosts that link are little-endian, as the objects are */
}

static void note_debug_sections(MsSpan data, size_t command, uint32_t size, MachoSymbols *out) {
  uint32_t sections = word32(data, command + 64);
  MsSpan wanted = ms_span_of((const uint8_t *)"__debug_info", sizeof "__debug_info"); /* with its NUL */
  for (uint32_t index = 0; index < sections && SEGMENT_SIZE + (size_t)(index + 1) * SECTION_SIZE <= size; index++) {
    size_t at = command + SEGMENT_SIZE + (size_t)index * SECTION_SIZE;
    out->debug = out->debug || ms_span_starts_with(ms_span_of(data.ptr + at, SECTION_SIZE), wanted);
  }
}

static void note_symbol(MsSpan data, size_t entry, size_t strings, uint32_t string_size, MachoSymbols *out) {
  uint32_t name = word32(data, entry);
  uint8_t type = data.ptr[entry + 4];
  bool global = (type & N_STAB) == 0 && (type & (N_EXT | N_PEXT)) == N_EXT && name < string_size;
  if (!global) {
    return;
  }
  size_t length = 0;
  while (name + length < string_size && data.ptr[strings + name + length] != 0) {
    length++;
  }
  if (length == 0) {
    return;
  }
  MsSpan symbol = ms_span_of(data.ptr + strings + name, length);
  bool undefined = (type & N_TYPE) == 0 && ms_load64(data.ptr + entry + 8) == 0;
  ms_span_list_push(undefined ? &out->undefined : &out->defined, symbol);
}

static void note_symbol_table(MsSpan data, size_t command, MachoSymbols *out) {
  uint32_t symbol_offset = word32(data, command + 8);
  uint32_t symbol_count = word32(data, command + 12);
  uint32_t string_offset = word32(data, command + 16);
  uint32_t string_size = word32(data, command + 20);
  if (!within(data.len, symbol_offset, (uint64_t)symbol_count * NLIST_SIZE) || !within(data.len, string_offset, string_size)) {
    return;
  }
  for (uint32_t index = 0; index < symbol_count; index++) {
    note_symbol(data, symbol_offset + (size_t)index * NLIST_SIZE, string_offset, string_size, out);
  }
}

static void read_object(MsSpan data, MachoSymbols *out) {
  if (data.len < HEADER_SIZE || word32(data, 0) != MACHO_MAGIC_64) {
    return;
  }
  uint32_t commands = word32(data, 16);
  size_t at = HEADER_SIZE;
  for (uint32_t index = 0; index < commands && within(data.len, at, 8); index++) {
    uint32_t command = word32(data, at);
    uint32_t size = word32(data, at + 4);
    if (size < 8 || !within(data.len, at, size)) {
      return;
    }
    if (command == LC_SEGMENT_64 && size >= SEGMENT_SIZE) {
      note_debug_sections(data, at, size, out);
    } else if (command == LC_SYMTAB && size >= 24) {
      note_symbol_table(data, at, out);
    }
    at += size;
  }
}

/* The decimal number in `field`, up to its padding spaces. */
static size_t decimal(MsSpan field) {
  size_t value = 0;
  for (size_t index = 0; index < field.len && ms_ascii_is_digit(field.ptr[index]); index++) {
    value = value * 10 + (size_t)(field.ptr[index] - '0');
  }
  return value;
}

void macho_collect(MsSpan data, MachoSymbols *out) {
  MsSpan magic = ms_span_of_text("!<arch>\n");
  if (!ms_span_starts_with(data, magic)) {
    read_object(data, out);
    return;
  }
  size_t at = magic.len;
  while (within(data.len, at, ARCHIVE_HEADER_SIZE)) {
    MsSpan header = ms_span_of(data.ptr + at, ARCHIVE_HEADER_SIZE);
    size_t size = decimal(ms_span_of(header.ptr + ARCHIVE_SIZE_OFFSET, ARCHIVE_SIZE_DIGITS));
    size_t body = at + ARCHIVE_HEADER_SIZE;
    if (!within(data.len, body, size)) {
      return;
    }
    /* BSD archives put a long member name at the start of its data: `#1/N`. */
    size_t skip = ms_span_starts_with(header, ms_span_of_text("#1/")) ? decimal(ms_span_of(header.ptr + 3, 13)) : 0;
    if (skip <= size) {
      read_object(ms_span_of(data.ptr + body + skip, size - skip), out);
    }
    at = body + size + (size & 1);
  }
}

void macho_free(MachoSymbols *symbols) {
  ms_span_list_free(&symbols->defined);
  ms_span_list_free(&symbols->undefined);
}
