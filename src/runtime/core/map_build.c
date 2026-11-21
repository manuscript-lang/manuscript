/* runtime/core/map_build.c: natives that fill a map from literal data: a packed table of constants and the
 * members of a JSON object. */
#include "runtime/core/map.h"

#include "runtime/core/fault.h"
#include "runtime/core/string.h"

/* A cursor over a literal table. */
typedef struct TableReader {
  MsSpan rest;
} TableReader;

static MS_NORETURN void bad_table_fault(void) {
  ms_fault_text(MS_FAULT_KIND_FAULT, "runtime invariant: malformed map table");
}

/* Decodes one item of a literal table into `out`, a slot of `size` bytes: tag 0 and an 8-byte word (an Int,
 * the bits of a Float, a Bool as 0 or 1), or tag 1, a u32 length and that many bytes (a String). The
 * compiler wrote the table, so a short one is a compiler bug. */
static void read_item(TableReader *reader, uint8_t *out, size_t size) {
  MsSpan rest = reader->rest;
  if (rest.len < 1) {
    bad_table_fault();
  }
  const uint8_t tag = rest.ptr[0];
  rest = ms_span_of(rest.ptr + 1, rest.len - 1);
  if (tag == 0) {
    if (rest.len < sizeof(uint64_t)) {
      bad_table_fault();
    }
    __builtin_memcpy(out, rest.ptr, size < sizeof(uint64_t) ? size : sizeof(uint64_t));
    reader->rest = ms_span_of(rest.ptr + sizeof(uint64_t), rest.len - sizeof(uint64_t));
    return;
  }
  uint32_t length = 0;
  if (rest.len < sizeof length) {
    bad_table_fault();
  }
  __builtin_memcpy(&length, rest.ptr, sizeof length);
  if (length > rest.len - sizeof length || size != sizeof(MsString)) {
    bad_table_fault();
  }
  const uint8_t *bytes = rest.ptr + sizeof length;
  msrt_string_from_bytes(bytes, length, (MsString *)__builtin_assume_aligned(out, _Alignof(MsString)));
  reader->rest = ms_span_of(bytes + length, rest.len - sizeof length - length);
}

/* Adds the entries of a packed table of constants, in order, so a later entry replaces an earlier one with
 * an equal key. The compiler emits the table for a literal whose keys and values are all constants. */
void msrt_map_add_table(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const MsString *table) {
  kd = ms_map_key_desc(m, kd);
  TableReader reader = {.rest = ms_string_span(table)};
  _Alignas(16) uint64_t key[2] = {0, 0};
  _Alignas(16) uint64_t value[2] = {0, 0};
  while (reader.rest.len > 0) {
    read_item(&reader, (uint8_t *)key, kd->size);
    read_item(&reader, (uint8_t *)value, vd != NULL ? vd->size : 0);
    ms_map_insert(m, kd, vd, (uint8_t *)key, (uint8_t *)value);
  }
}

/* Fills the empty map `m` (no storage) from `n` string keys and values `stride` bytes apart, consuming them.
 * Returns -1, or the index of the first repeated key: members before it are in the map, the caller keeps
 * ownership of the rest. */
int64_t msrt_map_fill_strings(MsMap *m, const MsTypeDesc *vd, MsString *keys, uint8_t *vals, int64_t stride,
                              int64_t n) {
  m->desc = &ms_desc_string;
  if (n <= 0) {
    return -1;
  }
  ms_map_reserve(m, &ms_desc_string, vd, (size_t)n);
  for (int64_t i = 0; i < n; i++) {
    uint8_t *key = (uint8_t *)&keys[i];
    if (ms_map_has(m, &ms_desc_string, vd, key)) {
      return i;
    }
    ms_map_insert(m, &ms_desc_string, vd, key, vals + i * stride);
  }
  return -1;
}
