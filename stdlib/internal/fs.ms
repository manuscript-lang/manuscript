import (
	Bytes from "@std/bytes.ms",
	Directory,
	DirectoryEntry,
	FileEvent,
	FileHandle,
	FileInfo,
	FileSystemInfo,
	NativeDirectory,
	NativeFile,
	NativeTemporary,
	NativeWatcher,
	PathEntry,
	RawWatcher,
	TemporaryDirectory from "@std/os/fs.ms",
	Duration, Timestamp from "@std/time.ms",
)

// Copies a file or tree. `flags` has recursive 1, replace 2, error on an existing
// destination 4, dereference 8, preserve timestamps 16 and verbatim symlinks 32;
// `clone` is "none", "try" or "force"; `filter` is called with the source and
// destination of each entry and skips it when it returns False.
@words=5 "file or directory not found"
export extern fn msstd_fs_copy(
	source: String,
	destination: String,
	flags: Int,
	clone: String,
	max_entries: Int?,
	max_bytes: Int?,
	filter: (fn(String, String) Bool)?,
) Void!

// The sorted matches of `patterns` under `path` that `exclude` and the filter do not
// leave out; the filter is called with an entry's path, name, directory flag and
// symlink flag and skips the entry when it returns True.
@words=5 "file or directory not found"
export extern fn msstd_fs_glob_entries(
	path: String,
	patterns: List[String],
	exclude: List[String],
	follow_links: Bool,
	max_entries: Int?,
	max_results: Int?,
	filter: (fn(String, String, Bool, Bool) Bool)?,
) move List[PathEntry]!

@words=5 "file or directory not found"
export extern fn msstd_io_close(file: NativeFile) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_clone(file: NativeFile) move FileHandle!

@words=5 "file or directory not found"
export extern fn msstd_io_read(file: NativeFile, max_bytes: Int?) move Bytes?!

@words=5 "file or directory not found"
export extern fn msstd_io_write(file: NativeFile, data: String) Void!

@words=5 "file or directory not found"
export extern fn msstd_io_write_bytes(file: NativeFile, data: Bytes) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_read_at(
	file: NativeFile,
	offset: Int,
	max_bytes: Int?,
) move Bytes!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_write_at(
	file: NativeFile,
	offset: Int,
	data: Bytes,
) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_read_file(file: NativeFile, max_bytes: Int?) move Bytes!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_read_vectors(
	file: NativeFile,
	sizes: List[Int],
	offset: Int,
) move List[Bytes]!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_write_vectors(
	file: NativeFile,
	buffers: List[Bytes],
	offset: Int,
) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_seek(file: NativeFile, offset: Int, origin: Int) Int!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_stat(file: NativeFile) move FileInfo!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_truncate(file: NativeFile, size: Int) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_sync(file: NativeFile) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_data_sync(file: NativeFile) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_try_lock(file: NativeFile, exclusive: Bool) Int!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_unlock(file: NativeFile) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_chmod(file: NativeFile, mode: Int) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_chown(file: NativeFile, uid: Int, gid: Int) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_set_times(
	file: NativeFile,
	accessed: Timestamp,
	modified: Timestamp,
) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_file_read_lines(
	file: NativeFile,
	max_bytes: Int?,
	max_lines: Int?,
) move List[String]!

@words=5 "file or directory not found"
export extern fn msstd_fs_directory_read(dir: NativeDirectory) move DirectoryEntry?!

@words=5 "file or directory not found"
export extern fn msstd_fs_directory_path(dir: NativeDirectory) move String

@words=5 "file or directory not found"
export extern fn msstd_fs_directory_close(dir: NativeDirectory) Void

@words=5 "file or directory not found"
export extern fn msstd_fs_watch_next(watcher: NativeWatcher) move List[FileEvent]?!

@words=5 "file or directory not found"
export extern fn msstd_fs_watch_close(watcher: NativeWatcher) Void

@words=5 "file or directory not found"
export extern fn msstd_fs_temporary_path(temporary: NativeTemporary) move String

@words=5 "file or directory not found"
export extern fn msstd_fs_temporary_close(temporary: NativeTemporary) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_canonicalize(path: String) move String!

@words=5 "file or directory not found"
export extern fn msstd_fs_create_directory(path: String, recursive: Bool) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_create_link(path: String, target: String) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_read_file(path: String, max_bytes: Int?) move Bytes!

@words=5 "file or directory not found"
export extern fn msstd_fs_read_link(path: String) move String!

@words=5 "file or directory not found"
export extern fn msstd_fs_remove(path: String, recursive: Bool) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_rename(source: String, destination: String) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_temporary_root() move String

@words=5 "file or directory not found"
export extern fn msstd_fs_temporary_directory(prefix: String) move String!

@words=5 "file or directory not found"
export extern fn msstd_fs_write_file(path: String, data: Bytes, replace: Bool) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_access(path: String, mode: Int) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_append_file(path: String, data: Bytes) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_chmod(path: String, mode: Int, follow: Bool) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_chown(path: String, uid: Int, gid: Int, follow: Bool) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_admit(bytes: Int) Bool

@words=5 "file or directory not found"
export extern fn msstd_fs_release() Void

@words=5 "file or directory not found"
export extern fn msstd_fs_truncate(path: String, size: Int) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_hard_link(source: String, destination: String) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_open(path: String, flags: String, mode: Int) move FileHandle!

@words=5 "file or directory not found"
export extern fn msstd_fs_directory_open(path: String) move Directory!

@words=5 "file or directory not found"
export extern fn msstd_fs_temporary_open(prefix: String) move TemporaryDirectory!

@words=5 "file or directory not found"
export extern fn msstd_fs_stat(path: String, follow: Bool) move FileInfo!

@words=5 "file or directory not found"
export extern fn msstd_fs_exists(path: String, follow: Bool) Int!

@words=5 "file or directory not found"
export extern fn msstd_fs_list(path: String, max_entries: Int?) move List[DirectoryEntry]!

@words=5 "file or directory not found"
export extern fn msstd_fs_set_times(
	path: String,
	accessed: Timestamp,
	modified: Timestamp,
	follow: Bool,
) Void!

@words=5 "file or directory not found"
export extern fn msstd_fs_stat_filesystem(path: String) move FileSystemInfo!

@words=5 "file or directory not found"
export extern fn msstd_fs_watch(
	path: String,
	recursive: Bool,
	interval: Duration,
	max_entries: Int?,
) move RawWatcher!

@words=5 "file or directory not found"
export extern fn msstd_fs_watch_native(
	path: String,
	recursive: Bool,
	max_entries: Int?,
	max_events: Int?,
	overflow: String,
) move RawWatcher!
