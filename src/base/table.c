/* Owns the part of the map table that knows nothing about keys: growth, compaction, removal, shape copy
 * (see map.h). Both tiers of the map use it, so a fix or tuning change lands in both. */
#include "base/alloc.h"
#include "base/fatal.h"
#include "base/map.h"

/* Entries below this many are never worth compacting after a removal. */
#define MS_TABLE_COMPACT_MIN_USED 32
#define MS_TABLE_MIN_CAPACITY 8

static size_t next_power_of_two(size_t n) {
  return n <= 1 ? 1 : (size_t)1 << (sizeof(size_t) * 8 - (size_t)__builtin_clzll(n - 1));
}

static size_t checked_bytes(size_t count, size_t size) {
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "map size overflow");
  }
  return bytes;
}

/* Replaces the index by an empty one of `index_size` words (a power of two) and links every live entry. */
static void rebuild_index(MsMap *map, const MsMapLayout *layout, size_t index_size) {
  ms_free(map->index);
  map->index = ms_alloc_zeroed(checked_bytes(index_size, sizeof(uint64_t)));
  map->mask = index_size - 1;
  for (size_t number = 0; number < map->used; number++) {
    const uint64_t hash = ms_table_entry_hash(ms_table_entry(map, layout, number));
    if ((hash & MS_MAP_LIVE) == 0) {
      continue;
    }
    size_t pos = ms_table_home(map, hash);
    while (map->index[pos] != 0) {
      pos = (pos + 1) & map->mask;
    }
    map->index[pos] = ms_table_index_word(hash, number);
  }
}

static void resize_slots(MsMap *map, const MsMapLayout *layout, size_t capacity) {
  const size_t bytes = checked_bytes(capacity, layout->stride);
  map->slots = map->slots == NULL ? ms_alloc(bytes) : ms_realloc(map->slots, bytes);
  map->cap = capacity;
}

/* Moves the live entries down over the holes and rebuilds the index. After a large drop (capacity at least
 * four times what the live entries need) the entries and the index shrink together, so the cost of the next
 * compaction follows the working size, not the historical peak. */
static void compact(MsMap *map, const MsMapLayout *layout) {
  size_t kept = 0;
  for (size_t number = 0; number < map->used; number++) {
    const uint8_t *entry = ms_table_entry(map, layout, number);
    if (!ms_table_entry_is_live(entry)) {
      continue;
    }
    if (kept != number) {
      __builtin_memmove(ms_table_entry(map, layout, kept), entry, layout->stride);
    }
    kept++;
  }
  map->used = kept;
  size_t capacity = next_power_of_two(map->len * 2);
  capacity = capacity < MS_TABLE_MIN_CAPACITY ? MS_TABLE_MIN_CAPACITY : capacity;
  if (capacity <= map->cap / 4) {
    resize_slots(map, layout, capacity);
  }
  rebuild_index(map, layout, map->cap * 2);
}

void ms_table_grow(MsMap *map, const MsMapLayout *layout) {
  if (map->used > 0 && map->len * 2 <= map->used && map->cap > 0) {
    compact(map, layout);
    return;
  }
  const size_t capacity = map->cap == 0 ? MS_TABLE_MIN_CAPACITY : map->cap * 2;
  if (capacity > MS_MAP_MAX_CAP) {
    ms_fatal(MS_FATAL_OVERFLOW, "map size overflow");
  }
  resize_slots(map, layout, capacity);
  rebuild_index(map, layout, capacity * 2);
}

void ms_table_reserve(MsMap *map, const MsMapLayout *layout, size_t count) {
  if (count <= map->cap || count > MS_MAP_MAX_CAP) {
    return;
  }
  size_t capacity = next_power_of_two(count);
  capacity = capacity < 2 ? 2 : capacity;
  resize_slots(map, layout, capacity);
  rebuild_index(map, layout, capacity * 2);
}

void ms_table_unlink(MsMap *map, const MsMapLayout *layout, uint64_t hash, size_t number) {
  size_t pos = ms_table_home(map, hash);
  while (map->index[pos] != ms_table_index_word(hash, number)) {
    pos = (pos + 1) & map->mask;
  }
  map->index[pos] = MS_MAP_INDEX_REMOVED;
  ms_store64(ms_table_entry(map, layout, number), 0);
  map->len--;
  if (map->used > MS_TABLE_COMPACT_MIN_USED && map->len < map->used / 2) {
    compact(map, layout);
  }
}

void ms_table_free(MsMap *map) {
  ms_free(map->slots);
  ms_free(map->index);
  *map = (MsMap){.desc = map->desc};
}

void ms_table_copy_shape(const MsMap *source, const MsMapLayout *layout, MsMap *out) {
  MsMap copy = {.desc = source->desc};
  if (source->len > 0) {
    size_t capacity = next_power_of_two(source->len);
    capacity = capacity < MS_TABLE_MIN_CAPACITY ? MS_TABLE_MIN_CAPACITY : capacity;
    resize_slots(&copy, layout, capacity);
    for (size_t number = 0; number < source->used; number++) {
      const uint8_t *from = ms_table_entry(source, layout, number);
      if (ms_table_entry_is_live(from)) {
        __builtin_memcpy(ms_table_entry(&copy, layout, copy.used++), from, layout->stride);
      }
    }
    copy.len = copy.used;
    rebuild_index(&copy, layout, copy.cap * 2);
  }
  *out = copy;
}
