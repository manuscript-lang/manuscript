/* The bundled zone database of @std/time: IANA zones as TZif version 2+ blocks, and Windows zone keys mapped
 * to IANA names. tools/tzdata/pack.py writes tzdata.bin; src/stdlib/internal/zone.ms reads the zones. */
#include "base/bytes.h"
#include "runtime/std/time.h"

extern const uint8_t ms_tzdata[];
extern const size_t ms_tzdata_size;

enum {
  HEADER_MAGIC = 4, /* "MSTZ" */
  WORD = 4,
};

static uint32_t word_at(size_t at) {
  const uint8_t *p = ms_tzdata + at;
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

/* The offset of the first index entry: after the magic, the version text and the entry count. */
static size_t index_start(size_t *count) {
  const size_t version_end = HEADER_MAGIC + WORD + word_at(HEADER_MAGIC);
  *count = word_at(version_end);
  return version_end + WORD;
}

void msstd_time_zone_data(const MsString *name, MsList *out) {
  *out = (MsList){0};
  const MsSpan wanted = ms_string_span(name);
  size_t count = 0;
  size_t at = index_start(&count);
  for (size_t i = 0; i < count; i++) {
    const size_t length = ms_tzdata[at];
    const MsSpan entry = ms_span_of(ms_tzdata + at + 1, length);
    const size_t data_at = at + 1 + length;
    if (ms_span_equal(entry, wanted)) {
      *out = ms_bytes_from_span(ms_span_of(ms_tzdata + word_at(data_at), word_at(data_at + WORD)));
      return;
    }
    at = data_at + 2 * WORD;
  }
}
