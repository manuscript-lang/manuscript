/* Owns the name table (see intern.h). */
#include "base/intern.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "base/hash.h"

#define MS_NAMES_INITIAL_TABLE 64

/* The slot where `text` is, or the empty slot where it would go. */
static size_t probe(const MsNames *names, MsSpan text, uint64_t hash) {
  const size_t mask = names->table_size - 1;
  size_t slot = (size_t)hash & mask;
  while (names->table[slot] != 0) {
    const MsName id = names->table[slot] - 1;
    if (names->hashes.ptr[id] == hash && ms_span_equal(names->spans.ptr[id], text)) {
      return slot;
    }
    slot = (slot + 1) & mask;
  }
  return slot;
}

static void rebuild_table(MsNames *names, size_t table_size) {
  ms_free(names->table);
  names->table = ms_alloc_zeroed(table_size * sizeof(uint32_t));
  names->table_size = table_size;
  const size_t mask = table_size - 1;
  for (size_t id = 0; id < names->spans.len; id++) {
    size_t slot = (size_t)names->hashes.ptr[id] & mask;
    while (names->table[slot] != 0) {
      slot = (slot + 1) & mask;
    }
    names->table[slot] = (uint32_t)id + 1;
  }
}

static MsName add_name(MsNames *names, MsSpan text, uint64_t hash) {
  if (names->spans.len >= UINT32_MAX - 1) {
    ms_fatal(MS_FATAL_OVERFLOW, "too many names");
  }
  ms_span_list_push(&names->spans, ms_arena_copy(&names->bytes, text));
  ms_hash_list_push(&names->hashes, hash);
  return (MsName)(names->spans.len - 1);
}

void ms_names_init(MsNames *names) {
  *names = (MsNames){.bytes = ms_arena_new()};
  rebuild_table(names, MS_NAMES_INITIAL_TABLE);
  const MsSpan empty = ms_span_of(NULL, 0);
  const uint64_t hash = ms_hash_span(empty);
  const MsName id = add_name(names, empty, hash);
  names->table[(size_t)hash & (names->table_size - 1)] = id + 1;
}

MsName ms_names_intern(MsNames *names, MsSpan text) {
  const uint64_t hash = ms_hash_span(text);
  size_t slot = probe(names, text, hash);
  if (names->table[slot] != 0) {
    return names->table[slot] - 1;
  }
  const MsName id = add_name(names, text, hash);
  if (names->spans.len * 2 > names->table_size) { /* keep the load under one half */
    rebuild_table(names, names->table_size * 2);
  } else {
    names->table[slot] = id + 1;
  }
  return id;
}

bool ms_names_find(const MsNames *names, MsSpan text, MsName *out) {
  const size_t slot = probe(names, text, ms_hash_span(text));
  if (names->table[slot] == 0) {
    return false;
  }
  *out = names->table[slot] - 1;
  return true;
}

MsSpan ms_names_span(const MsNames *names, MsName name) {
  if (name >= names->spans.len) {
    ms_fatal(MS_FATAL_OUT_OF_RANGE, "name id out of range");
  }
  return names->spans.ptr[name];
}

void ms_names_free(MsNames *names) {
  ms_free(names->table);
  ms_span_list_free(&names->spans);
  ms_hash_list_free(&names->hashes);
  ms_arena_free(&names->bytes);
  *names = (MsNames){0};
}
