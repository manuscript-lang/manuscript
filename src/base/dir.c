/* base/dir.h: the part that does not depend on the host. */
#include "base/dir.h"

void ms_dir_entries_free(MsDirEntryList *entries) {
  for (size_t i = 0; i < entries->len; i++) {
    ms_string_release(&entries->ptr[i].name);
  }
  ms_dir_entry_list_free(entries);
}
