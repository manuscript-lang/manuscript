/* ms_rt/fs.h: the @std/fs natives (src/runtime/std/fs*.c over src/runtime/sys). Fallible functions return a status
 * (0 ok, otherwise the runtime's STATUS_* code; STATUS_FAILED carries its text through `err`) and write their
 * result through an out parameter only on success. Symbols are listed in src/runtime/symbols/fs.txt. */
#ifndef MS_RT_FS_H
#define MS_RT_FS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain filesystem */

/* Records the natives share with compiled code. Strings and lists are runtime values. */

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

/* One PathEntry of glob_entries: the path, then the nested DirectoryEntry's name and two flag bytes. */
typedef struct MsFsPathEntry {
    MsStr path;
    MsStr name;
    uint8_t directory;
    uint8_t symlink;
} MsFsPathEntry;

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

/* Directory cursors and scoped temporary directories: handles the runtime drops (the Rust-free object header). */
/* ms-sig: msstd_fs_directory_open(path: *const StrVal, out: *mut *mut ObjCell<Directory>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_directory_open(const MsStr *path, void **out, MsStr *err);
/* ms-sig: msstd_fs_directory_read(handle h: *mut ObjCell<Directory>, out: *mut EntryOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_directory_read(void *handle, MsFsEntry *out, MsStr *err);
/* ms-sig: msstd_fs_directory_close(handle h: *mut ObjCell<Directory>) @domain=filesystem */
void msstd_fs_directory_close(void *handle);
/* ms-sig: msstd_fs_directory_path(handle h: *const ObjCell<Directory>, out: *mut StrVal) @domain=filesystem */
void msstd_fs_directory_path(const void *handle, MsStr *out);
/* ms-sig: msstd_fs_temporary_open(prefix: *const StrVal, out: *mut *mut ObjCell<Temporary>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_open(const MsStr *prefix, void **out, MsStr *err);
/* ms-sig: msstd_fs_temporary_path(handle h: *const ObjCell<Temporary>, out: *mut StrVal) @domain=filesystem */
void msstd_fs_temporary_path(const void *handle, MsStr *out);
/* ms-sig: msstd_fs_temporary_close(handle h: *mut ObjCell<Temporary>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_close(void *handle, MsStr *err);

/* Copies a file or tree. `clone` is "none", "try" or "force"; `filter` is null or a closure over (source, destination). */
/* ms-sig: msstd_fs_copy(source: *const StrVal, destination: *const StrVal, flags: i64, clone: *const StrVal, has_entries: HasRaw, entries: i64, has_bytes: HasRaw, bytes: i64, filter: *mut Closure, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_copy(const MsStr *source, const MsStr *destination, int64_t flags, const MsStr *clone, uint8_t has_entries, int64_t entries, uint8_t has_bytes, int64_t bytes, void *filter, MsStr *err);
/* The sorted matches of `patterns` under `path` that `exclude` and the filter (null, or a closure over (path, name,
 * directory, symlink)) do not leave out. */
/* ms-sig: msstd_fs_glob_entries(path: *const StrVal, patterns: *const VecVal, exclude: *const VecVal, follow_links: u8, has_max_entries: HasRaw, max_entries: i64, has_max_results: HasRaw, max_results: i64, filter: *mut Closure, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_glob_entries(const MsStr *path, const MsVec *patterns, const MsVec *exclude, uint8_t follow_links, uint8_t has_max_entries, int64_t max_entries, uint8_t has_max_results, int64_t max_results, void *filter, MsVec *out, MsStr *err);


/* File handles: a handle is the host stream of @std/io over an opened file (src/runtime/std/file.c). */
/* ms-sig: msstd_fs_open(path: *const StrVal, flags: *const StrVal, mode: i64, out: *mut *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_open(const MsStr *path, const MsStr *mode_text, int64_t mode, void **out, MsStr *err);
/* ms-sig: msstd_fs_file_clone(handle h: *const ObjCell<Stream>, out: *mut *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_clone(const void *handle, void **out, MsStr *err);
/* ms-sig: msstd_fs_file_read_at(handle h: *mut ObjCell<Stream>, offset: i64, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_at(void *handle, int64_t offset, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_fs_file_read_file(handle h: *mut ObjCell<Stream>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_file(void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_fs_file_write_at(handle h: *mut ObjCell<Stream>, offset: i64, data: *const VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_write_at(void *handle, int64_t offset, const MsVec *data, MsStr *err);
/* ms-sig: msstd_fs_file_read_vectors(handle h: *mut ObjCell<Stream>, sizes: *const VecVal, offset: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_vectors(void *handle, const MsVec *sizes, int64_t offset, MsVec *out, MsStr *err);
/* ms-sig: msstd_fs_file_write_vectors(handle h: *mut ObjCell<Stream>, buffers: *const VecVal, offset: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_write_vectors(void *handle, const MsVec *buffers, int64_t offset, MsStr *err);
/* ms-sig: msstd_fs_file_seek(handle h: *mut ObjCell<Stream>, offset: i64, origin: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_seek(void *handle, int64_t offset, int64_t origin, int64_t *out, MsStr *err);
/* ms-sig: msstd_fs_file_stat(handle h: *mut ObjCell<Stream>, out: *mut InfoOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_stat(void *handle, MsFsInfo *out, MsStr *err);
/* ms-sig: msstd_fs_file_truncate(handle h: *mut ObjCell<Stream>, size: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_truncate(void *handle, int64_t size, MsStr *err);
/* ms-sig: msstd_fs_file_sync(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_sync(void *handle, MsStr *err);
/* ms-sig: msstd_fs_file_data_sync(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_data_sync(void *handle, MsStr *err);
/* ms-sig: msstd_fs_file_try_lock(handle h: *mut ObjCell<Stream>, exclusive: u8, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_try_lock(void *handle, uint8_t exclusive, int64_t *out, MsStr *err);
/* ms-sig: msstd_fs_file_unlock(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_unlock(void *handle, MsStr *err);
/* ms-sig: msstd_fs_file_chmod(handle h: *mut ObjCell<Stream>, mode: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_chmod(void *handle, int64_t mode, MsStr *err);
/* ms-sig: msstd_fs_file_chown(handle h: *mut ObjCell<Stream>, uid: i64, gid: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_chown(void *handle, int64_t uid, int64_t gid, MsStr *err);
/* ms-sig: msstd_fs_file_set_times(handle h: *mut ObjCell<Stream>, accessed: *const Timestamp, modified: *const Timestamp, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_set_times(void *handle, const MsFsTimestamp *accessed, const MsFsTimestamp *modified, MsStr *err);
/* ms-sig: msstd_fs_file_read_lines(handle h: *mut ObjCell<Stream>, max_bytes: i64, max_lines: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_lines(void *handle, int64_t max_bytes, int64_t max_lines, MsVec *out, MsStr *err);

/* Watchers: a native one on libuv's file-event handles, a polling one that compares snapshots. A wait returns the
 * List[FileEvent]; STATUS_NONE once the watched root is gone, STATUS_CLOSED after close. */
/* ms-sig: msstd_fs_watch(path: *const StrVal, recursive: u8, interval_ns: i64, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch(const MsStr *path, uint8_t recursive, int64_t interval_ns, uint8_t has_max, int64_t max, void **out, MsStr *err);
/* ms-sig: msstd_fs_watch_close(handle h: *mut ObjCell<Watcher>) @domain=filesystem */
void msstd_fs_watch_close(void *handle);
/* ms-sig: msstd_fs_watch_native(path: *const StrVal, recursive: u8, has_max: HasRaw, max: i64, has_events: HasRaw, events: i64, overflow: *const StrVal, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch_native(const MsStr *path, uint8_t recursive, uint8_t has_max, int64_t max, uint8_t has_events, int64_t events, const MsStr *overflow, void **out, MsStr *err);
/* ms-sig: msstd_fs_watch_next(handle h: *mut ObjCell<Watcher>, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch_next(void *handle, MsVec *out, MsStr *err);

#endif
