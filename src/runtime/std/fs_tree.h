/* runtime/std/fs_tree.h: what the tree operations of @std/fs share (copy, glob): absolute and containment tests, a
 * directory read into packed names, and calls into program code. They run on the runtime thread, like the operations
 * that use them. */
#ifndef MS_RUNTIME_STD_FS_TREE_H
#define MS_RUNTIME_STD_FS_TREE_H

#include <stddef.h>

#include "runtime/std/fs_job.h"

/* `path` made absolute against the working directory (unchanged when that is unavailable), appended to `out`. */
void ms_fs_absolute(MsSpan path, MsStrBuild *out);

/* Whether `target` is `source` or lies inside it, by their cleaned names. */
bool ms_fs_within_path(MsSpan source, MsSpan target);

/* Names packed in a builder: each as its length, then its bytes. */
void ms_fs_names_push(MsStrBuild *names, MsSpan name);
/* The name at `*cursor`, advancing it; false at the end. The name is a view into `names`. */
bool ms_fs_names_next(MsSpan names, size_t *cursor, MsSpan *name);
bool ms_fs_names_contain(const MsStrBuild *names, MsSpan name);
/* The names in a directory, in native order. A failure to open or read is set in `fail` as an `open` failure of
 * `directory`. */
bool ms_fs_names_read(MsSpan directory, MsStrBuild *names, MsFail *fail);

/* ---- calling program code ---- */

/* A compiled closure: the object header, then the code the compiler built for its signature. Strings travel as their
 * two words. Program code can fault or be cancelled, which leaves by a jump: whoever calls it registers a cleanup. */
typedef struct MsFsClosure MsFsClosure;
typedef uint8_t (*MsFsPairCode)(MsFsClosure *closure, uint64_t first_word, uint64_t first_tag, uint64_t second_word,
                                uint64_t second_tag);
typedef uint8_t (*MsFsEntryCode)(MsFsClosure *closure, uint64_t first_word, uint64_t first_tag, uint64_t second_word,
                                 uint64_t second_tag, uint8_t directory, uint8_t symlink);
struct MsFsClosure {
  MsObj header;
  union {
    MsFsPairCode pair;
    MsFsEntryCode entry;
  } code;
};
_Static_assert(offsetof(MsFsClosure, code) == 16, "the compiler puts a closure's code after its header");

/* The two temporary strings a call passes; owned, released after the call or by the cleanup. */
typedef struct MsFsArguments {
  MsString first;
  MsString second;
  bool live;
} MsFsArguments;

void ms_fs_arguments_set(MsFsArguments *arguments, MsSpan first, MsSpan second);
void ms_fs_arguments_free(MsFsArguments *arguments);

#endif
