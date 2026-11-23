/* base/intern.h: MsNames, interned text with dense ids.
 *
 * Each distinct text gets a MsName, a small integer counted up from 0; id 0 is always the empty text, so a
 * zeroed MsName is valid. Equal texts have equal ids, so a compiler compares names by id, uses ids as array
 * indices and in bitsets, and never hashes a string on a hot path.
 *
 * Layout is flat: one arena holds the bytes, one array of spans is indexed by id, and one open-addressing
 * table of ids (with the hash kept in a parallel array) finds a text. Interning copies the text, so the
 * input may be freed afterwards; the span returned by ms_names_span lives until ms_names_free. */
#ifndef MS_BASE_INTERN_H
#define MS_BASE_INTERN_H

#include "base/arena.h"
#include "base/list.h"
#include "base/safe.h"

typedef uint32_t MsName;

#define MS_NAME_EMPTY ((MsName)0)

MS_LIST_DEFINE(MsSpanList, ms_span_list, MsSpan)
MS_LIST_DEFINE(MsHashList, ms_hash_list, uint64_t)

/* Whether the list holds a span equal to `value`. */
static inline bool ms_span_list_contains(const MsSpanList *list, MsSpan value) {
  for (size_t i = 0; i < list->len; i++) {
    if (ms_span_equal(list->ptr[i], value)) {
      return true;
    }
  }
  return false;
}

typedef struct MsNames {
  const struct MsNames *base; /* a frozen table whose ids come first, or NULL: see ms_names_init_over */
  uint32_t base_len;          /* the base's id count; this table's own ids start here */
  MsArena bytes;              /* owned: the interned texts */
  MsSpanList spans;           /* owned: by id - base_len */
  MsHashList hashes;          /* owned: by id - base_len */
  uint32_t *table;            /* owned: open addressing, own index + 1, 0 for an empty slot */
  size_t table_size;          /* a power of two */
} MsNames;

/* Starts a table holding the empty text as id 0. */
void ms_names_init(MsNames *names);

/* Starts a table layered over `base`, which must not change while this table or anything keyed by its ids lives: the
 * base's texts keep their ids, new texts get the ids after them, and the base is only read, so any number of tables
 * may share one across threads. */
void ms_names_init_over(MsNames *names, const MsNames *base);

/* The id of `text`, adding it when new. */
MsName ms_names_intern(MsNames *names, MsSpan text);

/* The id of `text` when already interned. */
MS_NODISCARD MS_NONNULL bool ms_names_find(const MsNames *names, MsSpan text, MsName *out);

/* The text of `name`; an id from another table or out of range reports through ms_fatal. */
MsSpan ms_names_span(const MsNames *names, MsName name);

static inline size_t ms_names_count(const MsNames *names) {
  return names->base_len + names->spans.len;
}

void ms_names_free(MsNames *names);

#endif
