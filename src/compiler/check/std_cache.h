/* compiler/check/std_cache.h: the bundled standard modules parsed once, for a process that checks many times.
 *
 * Parsing the bundled sources is a large share of a small check, and the sources are fixed per binary. The cache
 * parses every bundled module into one arena with one frozen name table. A check whose own table is layered over
 * that one (`ms_names_init_over(&names, ms_std_cache_names(cache))`) and is given the cache finds each bundled
 * module already parsed, its names already interned. Trees are never written by a check, so one cache serves any
 * number of checks, one after another or at once, and must outlive every program and name table built on it. */
#ifndef MS_COMPILER_CHECK_STD_CACHE_H
#define MS_COMPILER_CHECK_STD_CACHE_H

#include "base/intern.h"
#include "compiler/syntax/ast.h"

typedef struct MsStdCache MsStdCache;

/* Parses every bundled module. A module that does not parse is left out, so a check reports it as before. */
MS_NODISCARD MsStdCache *ms_std_cache_new(void);
void ms_std_cache_free(MsStdCache *cache);

/* The frozen names the trees use: the base of every table a check with this cache runs over. */
const MsNames *ms_std_cache_names(const MsStdCache *cache);

/* The parsed module whose file name (`@std/io/io.ms`) is `file` in the cache's names, or NULL. */
const MsModule *ms_std_cache_tree(const MsStdCache *cache, MsName file);

#endif
