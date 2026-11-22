/* compiler/own/live_set.c: the live place set, an array sorted by binding. */
#include "compiler/own/live_set.h"

MsLiveSet ms_live_clone(const MsLiveSet *set) {
  MsLiveSet copy = {0};
  if (set->len == 0) {
    return copy;
  }
  MsLiveEntry *room = ms_live_set_extend(&copy, set->len);
  for (size_t index = 0; index < set->len; index++) {
    room[index] = set->ptr[index];
  }
  return copy;
}

/* The first entry whose key is not below `key`. */
static size_t group_start(const MsLiveSet *set, uint64_t key) {
  size_t low = 0;
  size_t high = set->len;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    if (set->ptr[middle].key < key) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

static size_t group_end(const MsLiveSet *set, uint64_t key, size_t start) {
  size_t end = start;
  while (end < set->len && set->ptr[end].key == key) {
    end++;
  }
  return end;
}

static bool same_path(MsLivePath a, MsLivePath b) {
  if (a.len != b.len) {
    return false;
  }
  for (uint32_t index = 0; index < a.len; index++) {
    if (a.names[index] != b.names[index]) {
      return false;
    }
  }
  return true;
}

/* Whether one path is a prefix of the other. */
static bool related(MsLivePath a, MsLivePath b) {
  const uint32_t shared = a.len < b.len ? a.len : b.len;
  for (uint32_t index = 0; index < shared; index++) {
    if (a.names[index] != b.names[index]) {
      return false;
    }
  }
  return true;
}

static bool starts_with(MsLivePath path, MsLivePath prefix) {
  return path.len >= prefix.len && related(path, prefix);
}

static bool find_entry(const MsLiveSet *set, uint64_t key, MsLivePath path, size_t *at) {
  const size_t start = group_start(set, key);
  const size_t end = group_end(set, key, start);
  for (size_t index = start; index < end; index++) {
    if (same_path(set->ptr[index].path, path)) {
      *at = index;
      return true;
    }
  }
  *at = end;
  return false;
}

MsNode ms_live_get(const MsLiveSet *set, uint64_t key, MsLivePath path) {
  size_t at = 0;
  return find_entry(set, key, path, &at) ? set->ptr[at].node : MS_NO_NODE;
}

/* Opens a slot at `at` and returns it. */
static MsLiveEntry *open_slot(MsLiveSet *set, size_t at) {
  (void)ms_live_set_extend(set, 1);
  for (size_t index = set->len - 1; index > at; index--) {
    set->ptr[index] = set->ptr[index - 1];
  }
  return &set->ptr[at];
}

void ms_live_insert(MsLiveSet *set, uint64_t key, MsLivePath path, MsNode node) {
  size_t at = 0;
  if (find_entry(set, key, path, &at)) {
    set->ptr[at].node = node;
    return;
  }
  *open_slot(set, at) = (MsLiveEntry){.key = key, .path = path, .node = node};
}

static void merge_entry(MsLiveSet *set, const MsLiveEntry *entry) {
  size_t at = 0;
  if (!find_entry(set, entry->key, entry->path, &at)) {
    *open_slot(set, at) = *entry;
    return;
  }
  if (entry->node < set->ptr[at].node) {
    set->ptr[at].node = entry->node;
  }
}

void ms_live_join(MsLiveSet *into, const MsLiveSet *from) {
  if (into->len == 0) {
    MsLiveSet copy = ms_live_clone(from);
    ms_live_set_free(into);
    *into = copy;
    return;
  }
  for (size_t index = 0; index < from->len; index++) {
    merge_entry(into, &from->ptr[index]);
  }
}

/* Removes the entries of `key` (only those starting with `prefix` when given), compacting the array. */
static void remove_group(MsLiveSet *set, uint64_t key, const MsLivePath *prefix) {
  const size_t start = group_start(set, key);
  const size_t end = group_end(set, key, start);
  size_t kept = start;
  for (size_t index = start; index < end; index++) {
    if (prefix != NULL && !starts_with(set->ptr[index].path, *prefix)) {
      set->ptr[kept++] = set->ptr[index];
    }
  }
  for (size_t index = end; index < set->len; index++) {
    set->ptr[kept++] = set->ptr[index];
  }
  set->len = kept;
}

void ms_live_kill(MsLiveSet *set, uint64_t key) {
  remove_group(set, key, NULL);
}

void ms_live_remove_prefix(MsLiveSet *set, uint64_t key, MsLivePath prefix) {
  remove_group(set, key, &prefix);
}

MsNode ms_live_next_use(const MsLiveSet *set, uint64_t key, MsLivePath path) {
  const size_t start = group_start(set, key);
  const size_t end = group_end(set, key, start);
  MsNode best = MS_NO_NODE;
  for (size_t index = start; index < end; index++) {
    const MsLiveEntry *entry = &set->ptr[index];
    if (!related(entry->path, path)) {
      continue;
    }
    const bool store = entry->path.len > 0 && entry->path.names[entry->path.len - 1] == MS_LIVE_STORE;
    if (store) { /* a store to a field after the read does not read the value */
      continue;
    }
    if (entry->node < best) {
      best = entry->node;
    }
  }
  return best;
}
