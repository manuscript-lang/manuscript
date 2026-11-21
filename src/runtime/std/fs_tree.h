/* What the tree operations of @std/fs share (copy, glob): stats by byte path, absolute and containment tests, and a
 * directory read into a list of names. Runs on the runtime thread, like the operations that use it. */
#ifndef MS_STD_FS_TREE_H
#define MS_STD_FS_TREE_H

#include <stddef.h>

#include "fs_support.h"

/* A stat of `path` (following links when `follow`); a path the OS layer refuses is an invalid-argument error. */
MS_NODISCARD MsSysError ms_fs_stat_bytes(MsBytes path, bool follow, MsSysStat *out);

static inline bool ms_fs_stat_is_directory(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFDIR; }
static inline bool ms_fs_stat_is_link(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFLNK; }
static inline bool ms_fs_stat_is_regular(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFREG; }

/* `path` made absolute against the working directory (unchanged when that is unavailable). */
MS_NODISCARD bool ms_fs_absolute(MsBytes path, MsFsBuffer *out);

/* Whether `target` is `source` or lies inside it. False in `*within` is also the answer for out of memory, which is
 * reported by the return value. */
MS_NODISCARD bool ms_fs_within_path(MsBytes source, MsBytes target, bool *within);

/* The names in a directory, in native order, packed into `names` for ms_fs_names_next. A failure to open or read is
 * set in `fail` as an `open` failure of `directory`. */
MS_NODISCARD bool ms_fs_names_read(MsBytes directory, MsFsBuffer *names, MsFsFail *fail);
/* Appends a name as its length, then its bytes. */
MS_NODISCARD bool ms_fs_names_push(MsFsBuffer *names, MsBytes name);
/* The name at `*cursor`, advancing it; false at the end. The name is a view into `names`. */
bool ms_fs_names_next(const MsFsBuffer *names, size_t *cursor, MsBytes *name);
/* Whether `names` holds exactly `name`. */
bool ms_fs_names_contain(const MsFsBuffer *names, MsBytes name);

/* ---- calling program code ---- */

/* A compiled closure: the object header, then the code the compiler built for its signature. Strings travel as their
 * two words. Program code can fault or be cancelled, which leaves by a jump: whoever calls it registers a cleanup. */
typedef struct MsFsClosure MsFsClosure;
typedef uint8_t (*MsFsPairCode)(MsFsClosure *closure, uint64_t first_word, uint64_t first_tag, uint64_t second_word, uint64_t second_tag);
typedef uint8_t (*MsFsEntryCode)(MsFsClosure *closure, uint64_t first_word, uint64_t first_tag, uint64_t second_word, uint64_t second_tag,
                                 uint8_t directory, uint8_t symlink);
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
    MsStr first;
    MsStr second;
    bool live;
} MsFsArguments;

void ms_fs_arguments_set(MsFsArguments *arguments, MsBytes first, MsBytes second);
void ms_fs_arguments_free(MsFsArguments *arguments);

/* A cleanup the runtime runs when program code leaves by a jump (src/runtime/core/rt_calls.h). */
typedef void (*MsFsCleanupFn)(uint8_t *argument);
size_t msrt_cleanup_push(MsFsCleanupFn run, uint8_t *argument);
void msrt_cleanup_discard(size_t handle);

#endif
