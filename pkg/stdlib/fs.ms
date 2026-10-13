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
    # File length in bytes.
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp
    accessed: Timestamp
    changed: Timestamp
    mode: Int
    permissions: Int
    created: Optional[Timestamp]
    # Preferred I/O block size in bytes; unavailable fields are zero.
    block_size: Int
    # Allocated 512-byte blocks on POSIX hosts; unavailable fields are zero.
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
    # Opens a path using host flag bits in 0..2147483647 and permission bits in 0..4095.
    # Use fs.constants() on this host; unknown bits/combinations are left to the OS.
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
    # Watches native OS events; overflow is exactly `error` or `ignore` (case-sensitive).
    # Other policies return InvalidInput. Limits bound tracked paths and queued events.
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
    # Creates a new directory under the host temp root; the caller must remove it.
    # Prefix must be nonempty and contain no slash, backslash, or NUL.
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(
        path: String,
        data: Bytes,
        replace: Bool
    ) -> Result[Unit, FileSystemError]
    # Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined bits.
    # Native permissions and Windows access policy still apply.
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    # Changes target permissions with mode 0..4095; follows a final symbolic link.
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn chown(
        path: String,
        uid: Int,
        gid: Int,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    # Sets the target size in bytes; follows a final symbolic link.
    fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    fn set_times(
        path: String,
        accessed: Timestamp,
        modified: Timestamp,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    # Opens with exactly r, r+, w, wx, w+, wx+, a, ax, a+, or ax+; other strings return InvalidInput.
    # Mode is permission bits in 0..4095, applied on creation subject to umask/OS policy.
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
    # Creates a new temp directory whose contents are removed by scoped close.
    # Prefix has the same validation as temporary_directory; this does not query the temp root.
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    # Changes the link itself without following it; Unsupported on hosts lacking this operation.
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]

# An open file supporting sequential and positional I/O.
export interface FileHandle:
    # Adapts this handle to IoError/Optional chunk reads; closing either view closes all aliases.
    fn reader() -> ReadStream
    # Adapts complete writes to IoError/Unit; flush synchronizes the file.
    fn writer() -> WriteStream
    fn close() -> Unit
    # Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
    # Writes all bytes on success and returns their count; errors can leave a prefix without a count.
    fn write(data: Bytes) -> Result[Int, FileSystemError]
    # Writes at the current position; appends only when the handle was opened in append mode.
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    # Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.
    fn read_at(
        offset: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    # Writes all bytes at a nonnegative offset without moving the position; returns the full count.
    fn write_at(offset: Int, data: Bytes) -> Result[Int, FileSystemError]
    # Reads remaining bytes from the current position; EOF returns empty Bytes.
    fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    # Writes all bytes at the current position; does not truncate or reposition this handle.
    fn write_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_vectors(
        sizes: List[Int],
        offset: Int
    ) -> Result[List[Bytes], FileSystemError]
    # Writes every buffer and returns the total byte count; offset -1 uses the current position.
    fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Int, FileSystemError]
    # Seeks in bytes with origin exactly 0 (start), 1 (current), or 2 (end).
    # Other origins return InvalidInput; the OS validates the resulting offset.
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
    # Exactly `rename` (appearance/disappearance/rename) or `change` (contents/metadata).
    kind: String

# Capacity/free-space statistics: block_size is bytes, blocks/free/available are counts
# in those blocks, and files/files_free are native file-node counts (zero if unavailable).
export type FileSystemInfo:
    type_id: Int
    block_size: Int
    blocks: Int
    blocks_free: Int
    blocks_available: Int
    files: Int
    files_free: Int

# Returns this host's filesystem flag, mode, and permission constants by name.
# Names and values vary by host; absent entries are not supported constants or portable enum cases.
export fn constants() -> Map[String, Int]:

# Policies for recursive copies, including replacement, symlinks, and optional limits.
export type CopyOptions:
    recursive: Bool
    replace: Bool
    error_on_exists: Bool
    dereference: Bool
    preserve_timestamps: Bool
    verbatim_symlinks: Bool
    # Exactly `none`, `try`, or `force`; other strings return InvalidInput.
    # try falls back to byte copying; force requires a native clone operation.
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
