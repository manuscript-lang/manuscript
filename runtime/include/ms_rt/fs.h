/* ms_rt/fs.h: the @std/fs natives (runtime/std/fs*.c over runtime/sys). Fallible functions return a status
 * (0 ok, otherwise the runtime's STATUS_* code; STATUS_FAILED carries its text through `err`) and write their
 * result through an out parameter only on success. Symbols are listed in runtime/symbols/fs.txt. */
#ifndef MS_RT_FS_H
#define MS_RT_FS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain filesystem */

/* Records the natives share with compiled code (crates/ms-std-fs abi_type). Strings and lists are runtime values. */

/* FileInfo flattened: the name, then 64-bit words only. Times are seconds and nanoseconds; `kinds` is a bit set. */
typedef struct MsFsInfo {
    MsStr name;
    int64_t size, mode, permissions;
    int64_t modified_seconds, modified_nanos, accessed_seconds, accessed_nanos, changed_seconds, changed_nanos;
    int64_t created_seconds, created_nanos, created_present;
    int64_t kinds, block_size, blocks, rdev, device, inode, links, uid, gid;
} MsFsInfo;

/* A Timestamp at the layout the compiler gives the native time type. */
typedef struct MsFsTimestamp {
    int64_t seconds;
    int64_t nanos;
} MsFsTimestamp;

/* Filesystem status: type id, block size, blocks, free, available, files, free files. */
typedef struct MsFsFilesystem {
    int64_t kind, block_size, blocks, blocks_free, blocks_available, files, files_free;
} MsFsFilesystem;

/* One DirectoryEntry: the name, then two flag bytes. */
typedef struct MsFsEntry {
    MsStr name;
    uint8_t directory;
    uint8_t symlink;
} MsFsEntry;

/* Takes an admission permit for copying `bytes` for a pool job, parking while the pool is full. True when one is
 * held and msstd_fs_release must follow. */
/* ms-sig: msstd_fs_admit(bytes: i64) -> u8 */
uint8_t msstd_fs_admit(int64_t bytes);
/* Returns a permit from msstd_fs_admit. */
/* ms-sig: msstd_fs_release() */
void msstd_fs_release(void);

/* ms-sig: msstd_fs_access(path: *const StrVal, mode: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_access(const MsStr *path, int64_t mode, MsStr *err);
/* ms-sig: msstd_fs_append_file(path: *const StrVal, data: *const VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_append_file(const MsStr *path, const MsVec *data, MsStr *err);
/* ms-sig: msstd_fs_canonicalize(path: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_canonicalize(const MsStr *path, MsStr *out, MsStr *err);
/* ms-sig: msstd_fs_chmod(path: *const StrVal, mode: i64, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_chmod(const MsStr *path, int64_t mode, uint8_t follow, MsStr *err);
/* ms-sig: msstd_fs_chown(path: *const StrVal, uid: i64, gid: i64, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_chown(const MsStr *path, int64_t uid, int64_t gid, uint8_t follow, MsStr *err);
/* ms-sig: msstd_fs_create_directory(path: *const StrVal, recursive: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_create_directory(const MsStr *path, uint8_t recursive, MsStr *err);
/* ms-sig: msstd_fs_create_link(path: *const StrVal, target: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_create_link(const MsStr *path, const MsStr *target, MsStr *err);
/* 1 when the path names anything, 0 when it or a directory part is missing; other failures are errors. */
/* ms-sig: msstd_fs_exists(path: *const StrVal, follow: u8, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_exists(const MsStr *path, uint8_t follow, int64_t *out, MsStr *err);
/* ms-sig: msstd_fs_hard_link(source: *const StrVal, destination: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_hard_link(const MsStr *source, const MsStr *destination, MsStr *err);
/* Lists a directory sorted by name into a `List[DirectoryEntry]`. */
/* ms-sig: msstd_fs_list(path: *const StrVal, has_limit: HasRaw, limit: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_list(const MsStr *path, uint8_t has_limit, int64_t limit, MsVec *out, MsStr *err);
/* Reads a whole file as bytes. */
/* ms-sig: msstd_fs_read_file(path: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_read_file(const MsStr *path, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_fs_read_link(path: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_read_link(const MsStr *path, MsStr *out, MsStr *err);
/* ms-sig: msstd_fs_remove(path: *const StrVal, recursive: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_remove(const MsStr *path, uint8_t recursive, MsStr *err);
/* ms-sig: msstd_fs_rename(source: *const StrVal, destination: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_rename(const MsStr *source, const MsStr *destination, MsStr *err);
/* ms-sig: msstd_fs_set_times(path: *const StrVal, accessed: *const Timestamp, modified: *const Timestamp, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_set_times(const MsStr *path, const MsFsTimestamp *accessed, const MsFsTimestamp *modified, uint8_t follow, MsStr *err);
/* `follow` resolves a final symbolic link (stat), otherwise it reports the link (lstat). */
/* ms-sig: msstd_fs_stat(path: *const StrVal, follow: u8, out: *mut InfoOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_stat(const MsStr *path, uint8_t follow, MsFsInfo *out, MsStr *err);
/* ms-sig: msstd_fs_stat_filesystem(path: *const StrVal, out: *mut FsOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_stat_filesystem(const MsStr *path, MsFsFilesystem *out, MsStr *err);
/* ms-sig: msstd_fs_temporary_directory(pattern: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_directory(const MsStr *pattern, MsStr *out, MsStr *err);
/* ms-sig: msstd_fs_temporary_root(out: *mut StrVal) @domain=filesystem */
void msstd_fs_temporary_root(MsStr *out);
/* ms-sig: msstd_fs_truncate(path: *const StrVal, size: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_truncate(const MsStr *path, int64_t size, MsStr *err);
/* Writes bytes to a file (`replace` truncates, otherwise the file must not exist). */
/* ms-sig: msstd_fs_write_file(path: *const StrVal, data: *const VecVal, replace: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_write_file(const MsStr *path, const MsVec *data, uint8_t replace, MsStr *err);

#endif
