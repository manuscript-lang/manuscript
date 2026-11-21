/* base/dir.h: what a path is and what a directory holds. Paths are UTF-8 spans, `/` on every host. */
#ifndef MS_BASE_DIR_H
#define MS_BASE_DIR_H

#include "base/list.h"
#include "base/string.h"

typedef enum MsPathKind {
  MS_PATH_MISSING,
  MS_PATH_FILE,
  MS_PATH_DIRECTORY,
  MS_PATH_SYMLINK, /* a link, not followed */
  MS_PATH_OTHER
} MsPathKind;

/* The kind of the entry `path` names, without following a final link. */
MsPathKind ms_path_kind(MsSpan path);

typedef struct MsDirEntry {
  MsString name; /* owned: the entry's name as the file system spells it */
  MsPathKind kind;
} MsDirEntry;

MS_LIST_DEFINE(MsDirEntryList, ms_dir_entry_list, MsDirEntry)

/* Appends the entries of directory `path` ("." and ".." left out) in the order the host gives them. False when
 * the directory cannot be read; the C `errno` then holds the cause. */
MS_NODISCARD bool ms_dir_list(MsSpan path, MsDirEntryList *out);

/* Releases the names and the list. */
void ms_dir_entries_free(MsDirEntryList *entries);

#endif
