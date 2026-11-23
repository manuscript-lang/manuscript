/* Owns the parsed bundled standard modules (see std_cache.h). */
#include "compiler/check/std_cache.h"

#include "base/alloc.h"
#include "compiler/project/project.h"
#include "compiler/syntax/parse.h"

struct MsStdCache {
  MsNames names;
  MsArena arena;
  const MsModule **by_file; /* by name id of `@std/<name>`; NULL for every other name */
  size_t by_file_len;
};

MsStdCache *ms_std_cache_new(void) {
  MsStdCache *cache = ms_alloc_zeroed(sizeof *cache);
  ms_names_init(&cache->names);
  cache->arena = ms_arena_new();
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  MsModule **trees = MS_ARENA_NEW_ARRAY(&cache->arena, MsModule *, count == 0 ? 1 : count);
  MsName *files = MS_ARENA_NEW_ARRAY(&cache->arena, MsName, count == 0 ? 1 : count);
  for (size_t index = 0; index < count; index++) {
    MsStrBuild path = ms_strbuild_new();
    ms_strbuild_append_text(&path, "@std/");
    ms_strbuild_append(&path, sources[index].name);
    files[index] = ms_names_intern(&cache->names, ms_strbuild_span(&path));
    ms_strbuild_free(&path);
    MsModule *tree = MS_ARENA_NEW(&cache->arena, MsModule);
    MsDiag diag = {0};
    trees[index] = ms_parse(&cache->arena, &cache->names, sources[index].text, tree, &diag) ? tree : NULL;
  }
  cache->by_file_len = ms_names_count(&cache->names); /* the table is frozen from here on */
  cache->by_file = ms_alloc_zeroed(cache->by_file_len * sizeof *cache->by_file);
  for (size_t index = 0; index < count; index++) {
    cache->by_file[files[index]] = trees[index];
  }
  return cache;
}

void ms_std_cache_free(MsStdCache *cache) {
  if (cache == NULL) {
    return;
  }
  ms_free(cache->by_file);
  ms_arena_free(&cache->arena);
  ms_names_free(&cache->names);
  ms_free(cache);
}

const MsNames *ms_std_cache_names(const MsStdCache *cache) {
  return &cache->names;
}

const MsModule *ms_std_cache_tree(const MsStdCache *cache, MsName file) {
  return file < cache->by_file_len ? cache->by_file[file] : NULL;
}
