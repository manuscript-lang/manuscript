/* compiler/emit/emit_dead.c: drops the register definitions nothing reads.
 *
 * The emitter writes a MIR value's register where the value is made, and a use that takes the value through a stack
 * cell, a held result or a cell's address reads the cell and not the register: the `load`, `ptrtoint` or `add` that
 * made it stays unread (a quarter of the loads of the test executable of the router). Such a line has no effect;
 * LLVM would delete it, but only after reading it. A line that defines a register by a pure operation and whose register
 * is named nowhere else is dropped, and so are the lines that only fed it (found by counting names again, so a chain
 * goes away together). Loads that are volatile stay: Debug builds use them to keep a value in its frame slot. */
#include "compiler/emit/emit_func.h"

#include "base/alloc.h"
#include "base/hash.h"

typedef struct Name {
  size_t at, len; /* the register's name in the text, after `%` */
  uint32_t count; /* the times it is named, its definition included */
} Name;

typedef struct Names {
  Name *entries;
  size_t *index; /* open addressing over `entries`; SIZE_MAX empty */
  size_t mask, len;
} Names;

static bool name_byte(uint8_t byte) {
  return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') ||
         byte == '_' || byte == '.';
}

static Name *name_entry(Names *names, const uint8_t *text, size_t at, size_t len, bool add) {
  size_t slot = ms_hash_span(ms_span_of(text + at, len)) & names->mask;
  while (names->index[slot] != SIZE_MAX) {
    Name *entry = &names->entries[names->index[slot]];
    if (entry->len == len && __builtin_memcmp(text + entry->at, text + at, len) == 0) {
      return entry;
    }
    slot = (slot + 1) & names->mask;
  }
  if (!add) {
    return NULL;
  }
  names->entries[names->len] = (Name){.at = at, .len = len};
  names->index[slot] = names->len++;
  return &names->entries[names->len - 1];
}

/* Adds `delta` to the count of every register the line `[at, end)` names. */
static void count_line(Names *names, const uint8_t *text, size_t at, size_t end, bool add, int delta) {
  for (size_t pos = at; pos < end; pos++) {
    if (text[pos] != '%') {
      continue;
    }
    const size_t start = pos + 1;
    size_t stop = start;
    while (stop < end && name_byte(text[stop])) {
      stop++;
    }
    if (stop > start) {
      Name *entry = name_entry(names, text, start, stop - start, add);
      if (entry != NULL) {
        entry->count = (uint32_t)((int)entry->count + delta);
      }
    }
    pos = stop - 1;
  }
}

static bool starts(const uint8_t *text, size_t at, size_t end, const char *prefix) {
  size_t used = 0;
  while (prefix[used] != '\0') {
    if (at + used >= end || text[at + used] != (uint8_t)prefix[used]) {
      return false;
    }
    used++;
  }
  return true;
}

/* The register a line `  %name = <operation> ...` defines when the operation has no effect, else false. */
static bool pure_definition(const uint8_t *text, size_t at, size_t end, size_t *name, size_t *name_len) {
  if (!starts(text, at, end, "  %")) {
    return false;
  }
  *name = at + 3;
  size_t stop = *name;
  while (stop < end && name_byte(text[stop])) {
    stop++;
  }
  *name_len = stop - *name;
  if (*name_len == 0 || !starts(text, stop, end, " = ")) {
    return false;
  }
  static const char *const pure[] = {"getelementptr ", "load i", "load ptr", "load double", "load float", "ptrtoint ", "inttoptr ", "add ", "sub ",
                                     "mul ", "and ", "or ", "xor ", "shl ", "lshr ", "ashr ", "trunc ", "zext ",
                                     "sext ", "icmp ", "select ", "phi "};
  for (size_t index = 0; index < sizeof pure / sizeof pure[0]; index++) {
    if (starts(text, stop + 3, end, pure[index])) {
      return true;
    }
  }
  return false;
}

void emit_drop_dead_definitions(MsStrBuild *body) {
  const MsSpan span = ms_strbuild_span(body);
  const uint8_t *text = span.ptr;
  size_t lines = 1;
  size_t mentions = 0; /* the `%` signs: no more names than these are ever added */
  for (size_t at = 0; at < span.len; at++) {
    lines += text[at] == '\n' ? 1 : 0;
    mentions += text[at] == '%' ? 1 : 0;
  }
  Names names = {.entries = ms_alloc((mentions + 1) * sizeof(Name)), .mask = 1};
  while (names.mask < mentions * 2 + 2) {
    names.mask <<= 1;
  }
  names.index = ms_alloc(names.mask * sizeof(size_t));
  for (size_t slot = 0; slot < names.mask; slot++) {
    names.index[slot] = SIZE_MAX;
  }
  names.mask -= 1;
  count_line(&names, text, 0, span.len, true, 1);
  bool *dead = ms_alloc_zeroed(lines + 1);
  size_t dropped = 0;
  for (int round = 0; round < 8; round++) {
    bool changed = false;
    size_t number = 0;
    for (size_t at = 0; at < span.len; number++) {
      const uint8_t *newline = __builtin_memchr(text + at, '\n', span.len - at);
      const size_t end = newline == NULL ? span.len : (size_t)(newline - text);
      size_t name = 0;
      size_t name_len = 0;
      if (!dead[number] && pure_definition(text, at, end, &name, &name_len)) {
        const Name *entry = name_entry(&names, text, name, name_len, false);
        if (entry != NULL && entry->count == 1) {
          dead[number] = true;
          dropped++;
          changed = true;
          count_line(&names, text, at, end, false, -1);
        }
      }
      at = end + 1;
    }
    if (!changed) {
      break;
    }
  }
  if (dropped != 0) {
    MsStrBuild out = ms_strbuild_new();
    size_t number = 0;
    for (size_t at = 0; at < span.len; number++) {
      const uint8_t *newline = __builtin_memchr(text + at, '\n', span.len - at);
      const size_t end = newline == NULL ? span.len : (size_t)(newline - text);
      if (!dead[number]) {
        ms_strbuild_append(&out, ms_span_of(text + at, end - at));
        if (newline != NULL) {
          ms_strbuild_append_byte(&out, '\n');
        }
      }
      at = end + 1;
    }
    ms_strbuild_free(body);
    *body = out;
  }
  ms_free(dead);
  ms_free(names.entries);
  ms_free(names.index);
}
