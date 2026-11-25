/* compiler/mir/mir_hash.c: see mir_hash.h. */
#include "compiler/mir/mir_hash.h"

#include "base/sort.h"

static uint32_t slot_of(uint64_t key, uint32_t mask) {
  key ^= key >> 33;
  key *= UINT64_C(0xff51afd7ed558ccd);
  key ^= key >> 33;
  return (uint32_t)key & mask;
}

static uint32_t find(const MirHash *map, uint64_t key) {
  uint32_t index = slot_of(key, map->cap - 1);
  while (map->used[index] != 0 && map->key[index] != key) {
    index = (index + 1) & (map->cap - 1);
  }
  return index;
}

bool mh_get(const MirHash *map, uint64_t key, uint64_t *value) {
  if (map->cap == 0) {
    return false;
  }
  const uint32_t index = find(map, key);
  if (map->used[index] == 0) {
    return false;
  }
  if (value != NULL) {
    *value = map->val[index];
  }
  return true;
}

static void allocate(MsArena *arena, MirHash *map, uint32_t cap) {
  map->key = MS_ARENA_NEW_ARRAY(arena, uint64_t, cap);
  map->val = MS_ARENA_NEW_ARRAY(arena, uint64_t, cap);
  map->used = MS_ARENA_NEW_ARRAY(arena, uint8_t, cap);
  map->cap = cap;
  map->n = 0;
}

static void grow(MsArena *arena, MirHash *map) {
  const MirHash old = *map;
  allocate(arena, map, old.cap != 0 ? old.cap * 2 : 16);
  for (uint32_t index = 0; index < old.cap; index++) {
    if (old.used[index] == 0) {
      continue;
    }
    const uint32_t at = find(map, old.key[index]);
    map->used[at] = 1;
    map->key[at] = old.key[index];
    map->val[at] = old.val[index];
    map->n++;
  }
}

bool mh_put(MsArena *arena, MirHash *map, uint64_t key, uint64_t value) {
  if (map->cap == 0 || (map->n + 1) * 2 > map->cap) {
    grow(arena, map);
  }
  const uint32_t index = find(map, key);
  const bool fresh = map->used[index] == 0;
  if (fresh) {
    map->used[index] = 1;
    map->key[index] = key;
    map->n++;
  }
  map->val[index] = value;
  return fresh;
}

static int64_t compare_keys(uint8_t *env, const uint8_t *x, const uint8_t *y) {
  (void)env;
  uint64_t a = 0, b = 0;
  __builtin_memcpy(&a, x, sizeof a);
  __builtin_memcpy(&b, y, sizeof b);
  return a < b ? -1 : (a > b ? 1 : 0);
}

uint64_t *mh_keys(MsArena *arena, const MirHash *map) {
  uint64_t *out = MS_ARENA_NEW_ARRAY(arena, uint64_t, (size_t)map->n + 1);
  uint32_t count = 0;
  for (uint32_t index = 0; index < map->cap; index++) {
    if (map->used[index] != 0) {
      out[count++] = map->key[index];
    }
  }
  if (count > 1) {
    ms_sort((uint8_t *)out, count, sizeof *out, compare_keys, NULL);
  }
  return out;
}
