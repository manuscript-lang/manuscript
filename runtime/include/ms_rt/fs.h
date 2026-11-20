/* ms_rt/fs.h: the @std/fs natives (runtime/std/fs*.c over runtime/sys). Fallible functions return a status
 * (0 ok, otherwise the runtime's STATUS_* code; STATUS_FAILED carries its text through `err`) and write their
 * result through an out parameter only on success. Symbols are listed in runtime/symbols/fs.txt. */
#ifndef MS_RT_FS_H
#define MS_RT_FS_H

#include "ms_rt/base.h"

/* ms: domain filesystem */

/* Takes an admission permit for copying `bytes` for a pool job, parking while the pool is full. True when one is
 * held and msstd_fs_release must follow. */
/* ms-sig: msstd_fs_admit(bytes: i64) -> u8 */
uint8_t msstd_fs_admit(int64_t bytes);
/* Returns a permit from msstd_fs_admit. */
/* ms-sig: msstd_fs_release() */
void msstd_fs_release(void);

#endif
