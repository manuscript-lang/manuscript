import Bytes from "@std/bytes.ms"
import ReadStream, WriteStream from "@std/io/io.ms"
import (
    DirectoryEntry,
    FileEvent,
    FileHandle,
    FileInfo,
    FileSystem,
    FileSystemError,
    NativeDirectory,
    NativeFile,
    NativeTemporary,
    NativeWatcher,
    PathError,
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

export extern fn msstd_path_relative(base: String, target: String) String!PathError

export extern fn msstd_fs_posix() PathOperations

export extern fn msstd_fs_win32() PathOperations

export extern fn msstd_path_resolve(base: String, parts: List[String]) String!PathError

export extern fn msstd_path_parse(path: String) PathParts

export extern fn msstd_path_format(parts: PathParts) String

export extern fn msstd_path_matches_glob(path: String, pattern: String) Bool!PathError

export extern fn msstd_fs_file_reader(file: NativeFile) ReadStream

export extern fn msstd_fs_file_writer(file: NativeFile) WriteStream

export extern fn msstd_io_close(file: NativeFile) Unit

export extern fn msstd_fs_file_clone(file: NativeFile) FileHandle!FileSystemError

export extern fn msstd_io_read(file: NativeFile, max_bytes: Int?) Bytes?!FileSystemError

export extern fn msstd_io_write(file: NativeFile, data: String) Unit!FileSystemError

export extern fn msstd_io_write_bytes(
    file: NativeFile,
    data: Bytes
) Unit!FileSystemError

export extern fn msstd_fs_file_read_at(
    file: NativeFile,
    offset: Int,
    max_bytes: Int?
) Bytes!FileSystemError

export extern fn msstd_fs_file_write_at(
    file: NativeFile,
    offset: Int,
    data: Bytes
) Unit!FileSystemError

export extern fn msstd_fs_file_read_file(
    file: NativeFile,
    max_bytes: Int?
) Bytes!FileSystemError

export extern fn msstd_fs_file_read_vectors(
    file: NativeFile,
    sizes: List[Int],
    offset: Int
) List[Bytes]!FileSystemError

export extern fn msstd_fs_file_write_vectors(
    file: NativeFile,
    buffers: List[Bytes],
    offset: Int
) Unit!FileSystemError

export extern fn msstd_fs_file_seek(
    file: NativeFile,
    offset: Int,
    origin: Int
) Int!FileSystemError

export extern fn msstd_fs_file_stat(file: NativeFile) FileInfo!FileSystemError

export extern fn msstd_fs_file_truncate(
    file: NativeFile,
    size: Int
) Unit!FileSystemError

export extern fn msstd_fs_file_sync(file: NativeFile) Unit!FileSystemError

export extern fn msstd_fs_file_data_sync(file: NativeFile) Unit!FileSystemError

export extern fn msstd_fs_file_try_lock(
    file: NativeFile,
    exclusive: Bool
) Int!FileSystemError

export extern fn msstd_fs_file_unlock(file: NativeFile) Unit!FileSystemError

export extern fn msstd_fs_file_chmod(file: NativeFile, mode: Int) Unit!FileSystemError

export extern fn msstd_fs_file_chown(
    file: NativeFile,
    uid: Int,
    gid: Int
) Unit!FileSystemError

export extern fn msstd_fs_file_set_times(
    file: NativeFile,
    accessed: Timestamp,
    modified: Timestamp
) Unit!FileSystemError

export extern fn msstd_fs_file_read_lines(
    file: NativeFile,
    max_bytes: Int?,
    max_lines: Int?
) List[String]!FileSystemError

export extern fn msstd_fs_directory_read(
    dir: NativeDirectory
) DirectoryEntry?!FileSystemError

export extern fn msstd_fs_directory_path(dir: NativeDirectory) String

export extern fn msstd_fs_directory_close(dir: NativeDirectory) Unit

export extern fn msstd_fs_watch_next(
    watcher: NativeWatcher
) List[FileEvent]!FileSystemError

export extern fn msstd_fs_watch_close(watcher: NativeWatcher) Unit

export extern fn msstd_fs_temporary_path(temporary: NativeTemporary) String

export extern fn msstd_fs_temporary_close(
    temporary: NativeTemporary
) Unit!FileSystemError
