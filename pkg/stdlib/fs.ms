# Canonical standard-library declarations. Implementations are native.

import BigInt from "@std/bigint.ms"
import Bytes from "@std/bytes.ms"
import Map from "@std/collections.ms"
import List from "@std/collections.ms"
import ReadStream from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Duration from "@std/time.ms"
import Timestamp from "@std/time.ms"

# Errors returned by filesystem operations. `Failed` retains the host error text.
export type FileSystemError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)

# The name and kind flags for one child returned by a directory listing.
export type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool

# File metadata, including portable fields and exact platform-specific numeric values.
export type FileInfo:
    name: String
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp
    accessed: Timestamp
    changed: Timestamp
    mode: Int
    permissions: Int
    created: Optional[Timestamp]
    block_size: Int
    blocks: Int
    rdev: Int
    fifo: Bool
    socket: Bool
    block_device: Bool
    char_device: Bool
    exact: Map[String, BigInt]
    regular: Bool
    device: Int
    inode: Int
    links: Int
    uid: Int
    gid: Int

# Filesystem operations and resource factories for the current host.
export interface FileSystem:
    # Opens a path using host flag and mode bit values.
    fn open_flags(
        path: String,
        flags: Int,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    # Returns entries matching the supplied include and exclude patterns.
    fn glob_entries(
        path: String,
        options: GlobOptions,
        exclude: Optional[
            fn(
                entry: PathEntry
            ) -> Bool
        ]
    ) -> Result[List[PathEntry], FileSystemError]
    # Copies a file or tree according to the supplied replacement and size policies.
    fn copy(
        source: String,
        destination: String,
        options: CopyOptions,
        filter: Optional[
            fn(
                source: String,
                destination: String
            ) -> Bool
        ]
    ) -> Result[Unit, FileSystemError]
    # Watches filesystem changes. Limits bound tracked paths and queued events.
    fn watch_native(
        path: String,
        recursive: Bool,
        max_entries: Optional[Int] = none,
        max_events: Optional[Int] = none,
        overflow: String
    ) -> Result[FileWatcher, FileSystemError]
    # Resolves symlinks and returns the canonical absolute path.
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    # Copies one file; existing destinations are replaced only when requested.
    fn copy_file(
        source: String,
        destination: String,
        replace: Bool,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    # Creates a directory, optionally creating missing parents.
    fn create_directory(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    # Creates a symbolic link at `path` pointing to `target`.
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    # Lists a directory, optionally limiting the number of returned entries.
    fn list(
        path: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[DirectoryEntry], FileSystemError]
    # Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.
    fn read_file(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    fn read_link(path: String) -> Result[String, FileSystemError]
    fn remove(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(
        path: String,
        data: Bytes,
        replace: Bool
    ) -> Result[Unit, FileSystemError]
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn chown(
        path: String,
        uid: Int,
        gid: Int,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    fn set_times(
        path: String,
        accessed: Timestamp,
        modified: Timestamp,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn open(
        path: String,
        flags: String,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    fn open_directory(path: String) -> Result[Directory, FileSystemError]
    fn copy_tree(
        source: String,
        destination: String,
        replace: Bool,
        max_entries: Optional[Int] = none,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    fn glob(
        path: String,
        pattern: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]
    fn watch(
        path: String,
        recursive: Bool,
        interval: Duration,
        max_entries: Optional[Int] = none
    ) -> Result[FileWatcher, FileSystemError]
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]

# An open file supporting sequential and positional I/O.
export interface FileHandle:
    fn reader() -> ReadStream
    fn writer() -> WriteStream
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
    fn write(data: Bytes) -> Result[Int, FileSystemError]
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_at(
        offset: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    fn write_at(offset: Int, data: Bytes) -> Result[Int, FileSystemError]
    fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    fn write_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_vectors(
        sizes: List[Int],
        offset: Int
    ) -> Result[List[Bytes], FileSystemError]
    fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Int, FileSystemError]
    fn seek(offset: Int, origin: Int) -> Result[Int, FileSystemError]
    fn stat() -> Result[FileInfo, FileSystemError]
    fn truncate(size: Int) -> Result[Unit, FileSystemError]
    fn sync() -> Result[Unit, FileSystemError]
    fn data_sync() -> Result[Unit, FileSystemError]
    fn chmod(mode: Int) -> Result[Unit, FileSystemError]
    fn chown(uid: Int, gid: Int) -> Result[Unit, FileSystemError]
    fn set_times(
        accessed: Timestamp,
        modified: Timestamp
    ) -> Result[Unit, FileSystemError]
    fn read_lines(
        max_bytes: Optional[Int] = none,
        max_lines: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]

# An open directory that yields one child per read and must be closed.
export interface Directory:
    fn path() -> String
    fn close() -> Unit
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]

# A change stream returned by a filesystem watch operation.
export interface FileWatcher:
    fn close() -> Unit
    fn next() -> Result[List[FileEvent], FileSystemError]

# A temporary directory whose contents are removed when it is closed.
export interface TemporaryDirectory:
    fn close() -> Unit
    fn path() -> String

# One filesystem change and the affected path.
export type FileEvent:
    path: String
    kind: String

# Capacity and free-space statistics for the filesystem containing a path.
export type FileSystemInfo:
    type_id: Int
    block_size: Int
    blocks: Int
    blocks_free: Int
    blocks_available: Int
    files: Int
    files_free: Int

# Returns host filesystem flag, mode, and permission constants by name.
export fn constants() -> Map[String, Int]:

# Policies for recursive copies, including replacement, symlinks, and optional limits.
export type CopyOptions:
    recursive: Bool
    replace: Bool
    error_on_exists: Bool
    dereference: Bool
    preserve_timestamps: Bool
    verbatim_symlinks: Bool
    clone: String
    max_entries: Optional[Int] = none
    max_bytes: Optional[Int] = none

# A matched path together with its filesystem entry metadata.
export type PathEntry:
    path: String
    entry: DirectoryEntry

# Include and exclude patterns and limits used by filesystem glob operations.
export type GlobOptions:
    patterns: List[String]
    exclude: List[String]
    follow_links: Bool
    max_entries: Optional[Int] = none
    max_results: Optional[Int] = none

impl Error for FileSystemError:
    fn message() -> String:

# Returns filesystem operations for the current host.
export fn filesystem() -> FileSystem:
