/* Owns the cache permissions of package_cache.h, on libuv's synchronous calls. Port of `read_only` and the
 * `writable` pass of `remove_all` in crates/ms-cli/src/fetch.rs. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "driver/package_cache.h"

#include <uv.h>

#include "base/dir.h"
#include "base/ostext.h"
#include "base/strbuild.h"

enum { MODE_READ_EXECUTE = 0555, MODE_OWNER_WRITE = 0200, MODE_DIRECTORY_LOCKED = 0555, MODE_DIRECTORY_OPEN = 0755 };

static void change_mode(MsSpan path, bool locked, bool directory) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  int mode = directory ? (locked ? MODE_DIRECTORY_LOCKED : MODE_DIRECTORY_OPEN) : 0;
  if (!directory && uv_fs_stat(NULL, &request, name.ptr, NULL) == 0) {
    const int current = (int)uv_fs_get_statbuf(&request)->st_mode;
    mode = locked ? (current & MODE_READ_EXECUTE) : (current | MODE_OWNER_WRITE);
  }
  if (!directory) {
    uv_fs_req_cleanup(&request);
  }
#ifdef _WIN32
  if (!directory) {
    (void)uv_fs_chmod(NULL, &request, name.ptr, mode, NULL);
    uv_fs_req_cleanup(&request);
  }
#else
  (void)uv_fs_chmod(NULL, &request, name.ptr, mode, NULL);
  uv_fs_req_cleanup(&request);
#endif
  ms_os_text_free(&name);
}

static void walk(MsSpan dir, bool locked) {
  if (!locked) {
    change_mode(dir, false, true); /* open first, so the directory can be read and emptied */
  }
  MsDirEntryList entries = {0};
  if (ms_dir_list(dir, &entries)) {
    for (size_t i = 0; i < entries.len; i++) {
      MsStrBuild child = ms_strbuild_new();
      ms_strbuild_append(&child, dir);
      ms_strbuild_append_byte(&child, '/');
      ms_strbuild_append(&child, ms_string_span(&entries.ptr[i].name));
      if (entries.ptr[i].kind == MS_PATH_DIRECTORY) {
        walk(ms_strbuild_span(&child), locked);
      } else if (entries.ptr[i].kind == MS_PATH_FILE) {
        change_mode(ms_strbuild_span(&child), locked, false);
      }
      ms_strbuild_free(&child);
    }
  }
  ms_dir_entries_free(&entries);
  if (locked) {
    change_mode(dir, true, true);
  }
}

void ms_cache_protect(MsSpan dir) {
  walk(dir, true);
}

void ms_cache_unprotect(MsSpan dir) {
  walk(dir, false);
}
