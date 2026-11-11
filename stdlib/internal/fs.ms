// ms: words 5 file or directory not found
// ms: native msstd_fs_copy msstd_fs_glob_entries
import (
	Bytes from "@std/bytes.ms",
	Directory,
	DirectoryEntry,
	FileEvent,
	FileHandle,
	FileInfo,
	FileSystem,
	FileSystemInfo,
	NativeDirectory,
	NativeFile,
	NativeTemporary,
	NativeWatcher,
	RawWatcher,
	TemporaryDirectory from "@std/os/fs.ms",
	Duration, Timestamp from "@std/time.ms",
)

export extern fn msstd_fs_filesystem() FileSystem

export extern fn msstd_io_close(file: NativeFile) Unit!

export extern fn msstd_fs_file_clone(file: NativeFile) FileHandle!

export extern fn msstd_io_read(file: NativeFile, max_bytes: Int?) Bytes?!

export extern fn msstd_io_write(file: NativeFile, data: String) Unit!

export extern fn msstd_io_write_bytes(file: NativeFile, data: Bytes) Unit!

export extern fn msstd_fs_file_read_at(
	file: NativeFile,
	offset: Int,
	max_bytes: Int?,
) Bytes!

export extern fn msstd_fs_file_write_at(
	file: NativeFile,
	offset: Int,
	data: Bytes,
) Unit!

export extern fn msstd_fs_file_read_file(file: NativeFile, max_bytes: Int?) Bytes!

export extern fn msstd_fs_file_read_vectors(
	file: NativeFile,
	sizes: List[Int],
	offset: Int,
) List[Bytes]!

export extern fn msstd_fs_file_write_vectors(
	file: NativeFile,
	buffers: List[Bytes],
	offset: Int,
) Unit!

export extern fn msstd_fs_file_seek(file: NativeFile, offset: Int, origin: Int) Int!

export extern fn msstd_fs_file_stat(file: NativeFile) FileInfo!

export extern fn msstd_fs_file_truncate(file: NativeFile, size: Int) Unit!

export extern fn msstd_fs_file_sync(file: NativeFile) Unit!

export extern fn msstd_fs_file_data_sync(file: NativeFile) Unit!

export extern fn msstd_fs_file_try_lock(file: NativeFile, exclusive: Bool) Int!

export extern fn msstd_fs_file_unlock(file: NativeFile) Unit!

export extern fn msstd_fs_file_chmod(file: NativeFile, mode: Int) Unit!

export extern fn msstd_fs_file_chown(file: NativeFile, uid: Int, gid: Int) Unit!

export extern fn msstd_fs_file_set_times(
	file: NativeFile,
	accessed: Timestamp,
	modified: Timestamp,
) Unit!

export extern fn msstd_fs_file_read_lines(
	file: NativeFile,
	max_bytes: Int?,
	max_lines: Int?,
) List[String]!

export extern fn msstd_fs_directory_read(dir: NativeDirectory) DirectoryEntry?!

export extern fn msstd_fs_directory_path(dir: NativeDirectory) String

export extern fn msstd_fs_directory_close(dir: NativeDirectory) Unit

export extern fn msstd_fs_watch_next(watcher: NativeWatcher) List[FileEvent]!

export extern fn msstd_fs_watch_close(watcher: NativeWatcher) Unit

export extern fn msstd_fs_temporary_path(temporary: NativeTemporary) String

export extern fn msstd_fs_temporary_close(temporary: NativeTemporary) Unit!

export extern fn msstd_fs_canonicalize(path: String) String!

export extern fn msstd_fs_create_directory(path: String, recursive: Bool) Unit!

export extern fn msstd_fs_create_link(path: String, target: String) Unit!

export extern fn msstd_fs_read_file(path: String, max_bytes: Int?) Bytes!

export extern fn msstd_fs_read_link(path: String) String!

export extern fn msstd_fs_remove(path: String, recursive: Bool) Unit!

export extern fn msstd_fs_rename(source: String, destination: String) Unit!

export extern fn msstd_fs_temporary_root() String

export extern fn msstd_fs_temporary_directory(prefix: String) String!

export extern fn msstd_fs_write_file(path: String, data: Bytes, replace: Bool) Unit!

export extern fn msstd_fs_access(path: String, mode: Int) Unit!

export extern fn msstd_fs_append_file(path: String, data: Bytes) Unit!

export extern fn msstd_fs_chmod(path: String, mode: Int, follow: Bool) Unit!

export extern fn msstd_fs_chown(path: String, uid: Int, gid: Int, follow: Bool) Unit!

export extern fn msstd_fs_admit(bytes: Int) Bool

export extern fn msstd_fs_release() Unit

export extern fn msstd_fs_truncate(path: String, size: Int) Unit!

export extern fn msstd_fs_hard_link(source: String, destination: String) Unit!

export extern fn msstd_fs_open(path: String, flags: String, mode: Int) FileHandle!

export extern fn msstd_fs_directory_open(path: String) Directory!

export extern fn msstd_fs_temporary_open(prefix: String) TemporaryDirectory!

export extern fn msstd_fs_stat(path: String, follow: Bool) FileInfo!

export extern fn msstd_fs_list(path: String, max_entries: Int?) List[DirectoryEntry]!

export extern fn msstd_fs_set_times(
	path: String,
	accessed: Timestamp,
	modified: Timestamp,
	follow: Bool,
) Unit!

export extern fn msstd_fs_stat_filesystem(path: String) FileSystemInfo!

export extern fn msstd_fs_watch(
	path: String,
	recursive: Bool,
	interval: Duration,
	max_entries: Int?,
) RawWatcher!

export extern fn msstd_fs_watch_native(
	path: String,
	recursive: Bool,
	max_entries: Int?,
	max_events: Int?,
	overflow: String,
) RawWatcher!
