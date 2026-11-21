/* Unit test of base/map.h and base/desc.h: the erased and specialized tiers of maps and sets. */
#include <stdio.h>

#include "base/map.h"
#include "base/strbuild.h"

static int failures = 0;

#define CHECK(condition)                                                    \
  do {                                                                      \
    if (!(condition)) {                                                     \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
      failures++;                                                           \
    }                                                                       \
  } while (0)

MS_MAP_DEFINE(IdMap, id_map, uint32_t, uint64_t, ms_hash_u32_key, ms_equal_u32_key)
MS_SET_DEFINE(IdSet, id_set, uint32_t, ms_hash_u32_key, ms_equal_u32_key)

static MsString number_text(uint64_t value) {
  MsStrBuild builder = ms_strbuild_new();
  ms_strbuild_append_text(&builder, "key-number-");
  ms_strbuild_append_u64(&builder, value);
  const MsString text = ms_strbuild_finish(&builder);
  ms_strbuild_free(&builder);
  return text;
}

static void test_erased_string_map(void) {
  MsMap map = {0};
  for (int64_t i = 0; i < 200; i++) {
    MsString key = number_text((uint64_t)i);
    int64_t value = i * 10;
    ms_map_insert(&map, &ms_desc_string, &ms_desc_int, (uint8_t *)&key, (uint8_t *)&value);
  }
  CHECK(map.len == 200);
  MsString probe = number_text(77);
  const uint8_t *found = ms_map_get(&map, &ms_desc_string, &ms_desc_int, (const uint8_t *)&probe);
  CHECK(found != NULL && ms_load64(found) == 770);

  /* replacing an existing key drops the new key and keeps one entry */
  MsString again = number_text(77);
  int64_t replacement = 1;
  ms_map_insert(&map, &ms_desc_string, &ms_desc_int, (uint8_t *)&again, (uint8_t *)&replacement);
  CHECK(map.len == 200 && ms_load64(ms_map_get(&map, &ms_desc_string, &ms_desc_int, (uint8_t *)&probe)) == 1);

  for (uint64_t i = 0; i < 150; i++) {
    MsString key = number_text(i);
    CHECK(ms_map_remove(&map, &ms_desc_string, &ms_desc_int, (uint8_t *)&key));
    ms_string_release(&key);
  }
  CHECK(map.len == 50 && !ms_map_has(&map, &ms_desc_string, &ms_desc_int, (uint8_t *)&probe));

  MsMap copy = {0};
  ms_map_clone(&map, &ms_desc_string, &ms_desc_int, &copy);
  CHECK(ms_map_equal(&map, &copy, &ms_desc_string, &ms_desc_int));
  MsString last = number_text(199);
  CHECK(ms_map_remove(&copy, &ms_desc_string, &ms_desc_int, (uint8_t *)&last));
  CHECK(!ms_map_equal(&map, &copy, &ms_desc_string, &ms_desc_int));

  size_t cursor = 0;
  const uint8_t *key = NULL;
  const uint8_t *value = NULL;
  size_t seen = 0;
  int64_t first = -1;
  while (ms_map_next(&map, &ms_desc_string, &ms_desc_int, &cursor, &key, &value)) {
    first = seen == 0 ? (int64_t)ms_load64(value) : first;
    seen++;
  }
  CHECK(seen == 50 && first == 1500); /* insertion order survives removals */

  ms_string_release(&probe);
  ms_string_release(&last);
  ms_map_drop(&map, &ms_desc_string, &ms_desc_int);
  ms_map_drop(&copy, &ms_desc_string, &ms_desc_int);
  CHECK(map.len == 0 && map.slots == NULL);
}

static void test_erased_set_of_lists(void) {
  /* a set of strings: the set layout has no value */
  MsMap set = {0};
  for (uint64_t i = 0; i < 20; i++) {
    MsString key = number_text(i % 10);
    ms_map_insert(&set, &ms_desc_string, NULL, (uint8_t *)&key, NULL);
  }
  CHECK(set.len == 10);
  ms_map_drop(&set, &ms_desc_string, NULL);
}

static void test_specialized(void) {
  IdMap map = {0};
  IdSet set = {0};
  for (uint32_t i = 0; i < 5000; i++) {
    id_map_put(&map, i, (uint64_t)i * 2);
    CHECK(id_set_add(&set, i % 100) == (i < 100));
  }
  CHECK(map.table.len == 5000 && set.table.len == 100);
  CHECK(*id_map_get(&map, 4999) == 9998 && id_map_get(&map, 5000) == NULL);
  for (uint32_t i = 0; i < 5000; i += 2) {
    CHECK(id_map_remove(&map, i));
  }
  CHECK(map.table.len == 2500 && !id_map_has(&map, 4) && id_map_has(&map, 5));
  size_t cursor = 0;
  uint32_t key = 0;
  uint64_t *value = NULL;
  CHECK(id_map_next(&map, &cursor, &key, &value) && key == 1 && *value == 2);
  id_map_free(&map);
  id_set_free(&set);
}

int main(void) {
  test_erased_string_map();
  test_erased_set_of_lists();
  test_specialized();
  return failures == 0 ? 0 : 1;
}
