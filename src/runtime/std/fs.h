/* runtime/std/fs.h: the path-based @std/fs natives (fs_*.c) on libuv. Fallible natives return a status (0 ok,
 * otherwise MS_STATUS_*) and always fill `err`: empty unless the status is MS_STATUS_FAILED, which carries the host's
 * text, or the path a status names. The file-system calls run on the blocking pool (io/pool.h). Results are written
 * only on success. */
#ifndef MS_RUNTIME_STD_FS_H
#define MS_RUNTIME_STD_FS_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/desc.h"
#include "base/map.h"
#include "base/string.h"

/* A Timestamp at the layout the compiler gives the native time type. */
typedef struct MsFsTimestamp {
  int64_t seconds;
  int64_t nanos;
} MsFsTimestamp;

/* A FileInfo at the layout the compiler gives the record, field by field in declaration order: `kind` is the
 * FileKind case index, `exact` the Map[String, BigInt] of unbounded copies, and `created` an Optional Timestamp (its
 * presence flag, padded, then the Timestamp). */
typedef struct MsFsInfo {
  MsString name;
  int64_t size;
  int64_t kind;
  MsFsTimestamp modified, accessed, changed;
  int64_t mode, permissions, block_size, blocks, rdev;
  MsMap exact;
  int64_t device, inode, links, uid, gid;
  uint64_t created_present;
  MsFsTimestamp created;
} MsFsInfo;

_Static_assert(sizeof(MsFsInfo) == 240, "FileInfo layout");




/* Filesystem status: type id, block size, blocks, free, available, files, free files. */
typedef struct MsFsFilesystem {
  int64_t kind, block_size, blocks, blocks_free, blocks_available, files, files_free;
} MsFsFilesystem;

/* One DirectoryEntry: the name, then two flag bytes. */
typedef struct MsFsEntry {
  MsString name;
  uint8_t directory;
  uint8_t symlink;
} MsFsEntry;

/* Takes an admission permit for copying `bytes` for a pool job, parking while the pool is full. True when one is held
 * and msstd_fs_release must follow. */
/* ms-sig: msstd_fs_admit(bytes: i64) -> u8 */
uint8_t msstd_fs_admit(int64_t bytes);
/* Returns a permit from msstd_fs_admit. */
/* ms-sig: msstd_fs_release() */
void msstd_fs_release(void);

/* ms-sig: msstd_fs_access(path: *const StrVal, mode: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_access(const MsString *path, int64_t mode, MsString *err);
/* ms-sig: msstd_fs_append_file(path: *const StrVal, data: *const VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_append_file(const MsString *path, const MsBytes *data, MsString *err);
/* ms-sig: msstd_fs_canonicalize(path: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_canonicalize(const MsString *path, MsString *out, MsString *err);
/* ms-sig: msstd_fs_chmod(path: *const StrVal, mode: i64, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_chmod(const MsString *path, int64_t mode, uint8_t follow, MsString *err);
/* ms-sig: msstd_fs_chown(path: *const StrVal, uid: i64, gid: i64, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_chown(const MsString *path, int64_t uid, int64_t gid, uint8_t follow, MsString *err);
/* ms-sig: msstd_fs_create_directory(path: *const StrVal, recursive: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_create_directory(const MsString *path, uint8_t recursive, MsString *err);
/* ms-sig: msstd_fs_create_link(path: *const StrVal, target: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_create_link(const MsString *path, const MsString *target, MsString *err);
/* 1 when the path names anything, 0 when it or a directory part is missing; other failures are errors. */
/* ms-sig: msstd_fs_exists(path: *const StrVal, follow: u8, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_exists(const MsString *path, uint8_t follow, int64_t *out, MsString *err);
/* ms-sig: msstd_fs_hard_link(source: *const StrVal, destination: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_hard_link(const MsString *source, const MsString *destination, MsString *err);
/* Lists a directory sorted by name into a `List[DirectoryEntry]`. */
/* ms-sig: msstd_fs_list(path: *const StrVal, has_limit: HasRaw, limit: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_list(const MsString *path, uint8_t has_limit, int64_t limit, MsList *out, MsString *err);
/* Reads a whole file as bytes. */
/* ms-sig: msstd_fs_read_file(path: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_read_file(const MsString *path, uint8_t has_max, int64_t max, MsBytes *out, MsString *err);
/* ms-sig: msstd_fs_read_link(path: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_read_link(const MsString *path, MsString *out, MsString *err);
/* ms-sig: msstd_fs_remove(path: *const StrVal, recursive: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_remove(const MsString *path, uint8_t recursive, MsString *err);
/* ms-sig: msstd_fs_rename(source: *const StrVal, destination: *const StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_rename(const MsString *source, const MsString *destination, MsString *err);
/* ms-sig: msstd_fs_set_times(path: *const StrVal, accessed: *const Timestamp, modified: *const Timestamp, follow: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_set_times(const MsString *path, const MsFsTimestamp *accessed, const MsFsTimestamp *modified,
                           uint8_t follow, MsString *err);
/* `follow` resolves a final symbolic link (stat), otherwise it reports the link (lstat). */
/* ms-sig: msstd_fs_stat(path: *const StrVal, follow: u8, out: *mut InfoOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_stat(const MsString *path, uint8_t follow, MsFsInfo *out, MsString *err);
/* ms-sig: msstd_fs_stat_filesystem(path: *const StrVal, out: *mut FsOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_stat_filesystem(const MsString *path, MsFsFilesystem *out, MsString *err);
/* ms-sig: msstd_fs_temporary_directory(pattern: *const StrVal, out: *mut StrVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_directory(const MsString *pattern, MsString *out, MsString *err);
/* ms-sig: msstd_fs_temporary_root(out: *mut StrVal) @domain=filesystem */
void msstd_fs_temporary_root(MsString *out);
/* ms-sig: msstd_fs_truncate(path: *const StrVal, size: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_truncate(const MsString *path, int64_t size, MsString *err);
/* Writes bytes to a file (`replace` truncates, otherwise the file must not exist). */
/* ms-sig: msstd_fs_write_file(path: *const StrVal, data: *const VecVal, replace: u8, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_write_file(const MsString *path, const MsBytes *data, uint8_t replace, MsString *err);

/* Directory cursors and scoped temporary directories: handles the runtime drops. */
/* ms-sig: msstd_fs_directory_open(path: *const StrVal, out: *mut *mut ObjCell<Directory>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_directory_open(const MsString *path, MsObj **out, MsString *err);
/* The next entry in native order; MS_STATUS_NONE at the end. */
/* ms-sig: msstd_fs_directory_read(handle h: *mut ObjCell<Directory>, out: *mut EntryOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_directory_read(MsObj *handle, MsFsEntry *out, MsString *err);
/* ms-sig: msstd_fs_directory_close(handle h: *mut ObjCell<Directory>) @domain=filesystem */
void msstd_fs_directory_close(MsObj *handle);
/* ms-sig: msstd_fs_directory_path(handle h: *const ObjCell<Directory>, out: *mut StrVal) @domain=filesystem */
void msstd_fs_directory_path(const MsObj *handle, MsString *out);
/* ms-sig: msstd_fs_temporary_open(prefix: *const StrVal, out: *mut *mut ObjCell<Temporary>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_open(const MsString *prefix, MsObj **out, MsString *err);
/* ms-sig: msstd_fs_temporary_path(handle h: *const ObjCell<Temporary>, out: *mut StrVal) @domain=filesystem */
void msstd_fs_temporary_path(const MsObj *handle, MsString *out);
/* Removes the tree; a failure carries its text in `err`. */
/* ms-sig: msstd_fs_temporary_close(handle h: *mut ObjCell<Temporary>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_temporary_close(MsObj *handle, MsString *err);

/* File handles: a handle is the host stream (stream.h) over an opened file. */
/* ms-sig: msstd_fs_open(path: *const StrVal, flags: *const StrVal, mode: i64, out: *mut *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_open(const MsString *path, const MsString *mode_text, int64_t mode, MsObj **out, MsString *err);
/* ms-sig: msstd_fs_file_clone(handle h: *const ObjCell<Stream>, out: *mut *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_clone(const MsObj *handle, MsObj **out, MsString *err);
/* ms-sig: msstd_fs_file_read_at(handle h: *mut ObjCell<Stream>, offset: i64, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_at(MsObj *handle, int64_t offset, uint8_t has_max, int64_t max, MsBytes *out, MsString *err);
/* ms-sig: msstd_fs_file_read_file(handle h: *mut ObjCell<Stream>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_file(MsObj *handle, uint8_t has_max, int64_t max, MsBytes *out, MsString *err);
/* ms-sig: msstd_fs_file_write_at(handle h: *mut ObjCell<Stream>, offset: i64, data: *const VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_write_at(MsObj *handle, int64_t offset, const MsBytes *data, MsString *err);
/* ms-sig: msstd_fs_file_read_vectors(handle h: *mut ObjCell<Stream>, sizes: *const VecVal, offset: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_vectors(MsObj *handle, const MsList *sizes, int64_t offset, MsList *out, MsString *err);
/* ms-sig: msstd_fs_file_write_vectors(handle h: *mut ObjCell<Stream>, buffers: *const VecVal, offset: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_write_vectors(MsObj *handle, const MsList *buffers, int64_t offset, MsString *err);
/* ms-sig: msstd_fs_file_seek(handle h: *mut ObjCell<Stream>, offset: i64, origin: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_seek(MsObj *handle, int64_t offset, int64_t origin, int64_t *out, MsString *err);
/* ms-sig: msstd_fs_file_stat(handle h: *mut ObjCell<Stream>, out: *mut InfoOut, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_stat(MsObj *handle, MsFsInfo *out, MsString *err);
/* ms-sig: msstd_fs_file_truncate(handle h: *mut ObjCell<Stream>, size: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_truncate(MsObj *handle, int64_t size, MsString *err);
/* ms-sig: msstd_fs_file_sync(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_sync(MsObj *handle, MsString *err);
/* ms-sig: msstd_fs_file_data_sync(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_data_sync(MsObj *handle, MsString *err);
/* Tries an advisory lock on the whole file; 0 in `*out` when another handle holds a conflicting one. */
/* ms-sig: msstd_fs_file_try_lock(handle h: *mut ObjCell<Stream>, exclusive: u8, out: *mut i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_try_lock(MsObj *handle, uint8_t exclusive, int64_t *out, MsString *err);
/* ms-sig: msstd_fs_file_unlock(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_unlock(MsObj *handle, MsString *err);
/* ms-sig: msstd_fs_file_chmod(handle h: *mut ObjCell<Stream>, mode: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_chmod(MsObj *handle, int64_t mode, MsString *err);
/* ms-sig: msstd_fs_file_chown(handle h: *mut ObjCell<Stream>, uid: i64, gid: i64, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_chown(MsObj *handle, int64_t uid, int64_t gid, MsString *err);
/* ms-sig: msstd_fs_file_set_times(handle h: *mut ObjCell<Stream>, accessed: *const Timestamp, modified: *const Timestamp, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_set_times(MsObj *handle, const MsFsTimestamp *accessed, const MsFsTimestamp *modified,
                                MsString *err);
/* ms-sig: msstd_fs_file_read_lines(handle h: *mut ObjCell<Stream>, max_bytes: i64, max_lines: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_file_read_lines(MsObj *handle, int64_t max_bytes, int64_t max_lines, MsList *out, MsString *err);

/* Copies a file or tree. `clone` is "none", "try" or "force"; `filter` is null or a closure over (source, destination). */
/* ms-sig: msstd_fs_copy(source: *const StrVal, destination: *const StrVal, flags: i64, clone: *const StrVal, has_entries: HasRaw, entries: i64, has_bytes: HasRaw, bytes: i64, filter: *mut Closure, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_copy(const MsString *source, const MsString *destination, int64_t flags, const MsString *clone,
                      uint8_t has_entries, int64_t entries, uint8_t has_bytes, int64_t bytes, MsObj *filter,
                      MsString *err);

/* One PathEntry of glob_entries: the path, then the nested DirectoryEntry's name and two flag bytes. */
typedef struct MsFsPathEntry {
  MsString path;
  MsString name;
  uint8_t directory;
  uint8_t symlink;
} MsFsPathEntry;

/* The sorted matches of `patterns` under `path` that `exclude` and the filter (null, or a closure over (path, name,
 * directory, symlink)) do not leave out. */
/* ms-sig: msstd_fs_glob_entries(path: *const StrVal, patterns: *const VecVal, exclude: *const VecVal, follow_links: u8, has_max_entries: HasRaw, max_entries: i64, has_max_results: HasRaw, max_results: i64, filter: *mut Closure, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_glob_entries(const MsString *path, const MsList *patterns, const MsList *exclude, uint8_t follow_links,
                              uint8_t has_max_entries, int64_t max_entries, uint8_t has_max_results,
                              int64_t max_results, MsObj *filter, MsList *out, MsString *err);

/* One watcher event: the path, and `rename` (an entry appeared or went) or `change`. */
typedef struct MsFsEvent {
  MsString path;
  MsString kind;
} MsFsEvent;

/* ms-sig: msstd_fs_watch(path: *const StrVal, recursive: u8, interval_ns: i64, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch(const MsString *path, uint8_t recursive, int64_t interval_ns, uint8_t has_max, int64_t max,
                       MsObj **out, MsString *err);
/* ms-sig: msstd_fs_watch_native(path: *const StrVal, recursive: u8, has_max: HasRaw, max: i64, has_events: HasRaw, events: i64, overflow: *const StrVal, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch_native(const MsString *path, uint8_t recursive, uint8_t has_max, int64_t max, uint8_t has_events,
                              int64_t events, const MsString *overflow, MsObj **out, MsString *err);
/* The next batch of events (a list of MsFsEvent), parking until there is one; MS_STATUS_NONE once a watched root is gone. */
/* ms-sig: msstd_fs_watch_next(handle h: *mut ObjCell<Watcher>, out: *mut VecVal, err: ErrSlot) -> u8 @domain=filesystem */
uint8_t msstd_fs_watch_next(MsObj *handle, MsList *out, MsString *err);
/* ms-sig: msstd_fs_watch_close(handle h: *mut ObjCell<Watcher>) @domain=filesystem */
void msstd_fs_watch_close(MsObj *handle);

#endif
