import Bytes from "@std/bytes.ms"
import ReadStream, WriteStream from "@std/io/io.ms"
import (
    DirectoryEntry,
    FileEvent,
    FileHandle,
    FileInfo,
    FileSystem,
    NativeDirectory,
    NativeFile,
    NativeTemporary,
    NativeWatcher,
    PathOperations,
    PathParts
) from "@std/os/fs.ms"
import Timestamp from "@std/os/time.ms"

export extern fn msstd_fs_constants() Map[String, Int]

export extern fn msstd_path_basename(path: String) String

export extern fn msstd_path_dirname(path: String) String

export extern fn msstd_path_extension(path: String) String

export extern fn msstd_path_is_absolute(path: String) Bool

export extern fn msstd_path_join(parts: List[String]) String

export extern fn msstd_path_normalize(path: String) String

export extern fn msstd_path_basename_without(path: String, suffix: String) String

export extern fn msstd_path_separator() String

export extern fn msstd_path_delimiter() String

export extern fn msstd_path_to_namespaced_path(path: String) String

export extern fn msstd_fs_filesystem() FileSystem

export extern fn msstd_path_relative(base: String, target: String) String!

export extern fn msstd_fs_posix() PathOperations

export extern fn msstd_fs_win32() PathOperations

export extern fn msstd_path_resolve(base: String, parts: List[String]) String!

export extern fn msstd_path_parse(path: String) PathParts

export extern fn msstd_path_format(parts: PathParts) String

export extern fn msstd_path_matches_glob(path: String, pattern: String) Bool!

export extern fn msstd_fs_file_reader(file: NativeFile) ReadStream

export extern fn msstd_fs_file_writer(file: NativeFile) WriteStream

export extern fn msstd_io_close(file: NativeFile) Unit

export extern fn msstd_fs_file_clone(file: NativeFile) FileHandle!

export extern fn msstd_io_read(file: NativeFile, max_bytes: Int?) Bytes?!

export extern fn msstd_io_write(file: NativeFile, data: String) Unit!

export extern fn msstd_io_write_bytes(file: NativeFile, data: Bytes) Unit!

export extern fn msstd_fs_file_read_at(
    file: NativeFile,
    offset: Int,
    max_bytes: Int?
) Bytes!

export extern fn msstd_fs_file_write_at(
    file: NativeFile,
    offset: Int,
    data: Bytes
) Unit!

export extern fn msstd_fs_file_read_file(file: NativeFile, max_bytes: Int?) Bytes!

export extern fn msstd_fs_file_read_vectors(
    file: NativeFile,
    sizes: List[Int],
    offset: Int
) List[Bytes]!

export extern fn msstd_fs_file_write_vectors(
    file: NativeFile,
    buffers: List[Bytes],
    offset: Int
) Unit!

export extern fn msstd_fs_file_seek(file: NativeFile, offset: Int, origin: Int) Int!

export extern fn msstd_fs_file_stat(file: NativeFile) FileInfo!

export extern fn msstd_fs_file_truncate(file: NativeFile, size: Int) Unit!

export extern fn msstd_fs_file_sync(file: NativeFile) Unit!

export extern fn msstd_fs_file_data_sync(file: NativeFile) Unit!

export extern fn msstd_fs_file_chmod(file: NativeFile, mode: Int) Unit!

export extern fn msstd_fs_file_chown(file: NativeFile, uid: Int, gid: Int) Unit!

export extern fn msstd_fs_file_set_times(
    file: NativeFile,
    accessed: Timestamp,
    modified: Timestamp
) Unit!

export extern fn msstd_fs_file_read_lines(
    file: NativeFile,
    max_bytes: Int?,
    max_lines: Int?
) List[String]!

export extern fn msstd_fs_directory_read(dir: NativeDirectory) DirectoryEntry?!

export extern fn msstd_fs_directory_path(dir: NativeDirectory) String

export extern fn msstd_fs_directory_close(dir: NativeDirectory) Unit

export extern fn msstd_fs_watch_next(watcher: NativeWatcher) List[FileEvent]!

export extern fn msstd_fs_watch_close(watcher: NativeWatcher) Unit

export extern fn msstd_fs_temporary_path(temporary: NativeTemporary) String

export extern fn msstd_fs_temporary_close(temporary: NativeTemporary) Unit!
